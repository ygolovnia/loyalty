IF EXISTS (SELECT 1 FROM sysobjects where id = object_id(N'dbo.cbm_spGeneralStaffFreeTicket') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
	DROP PROCEDURE dbo.cbm_spGeneralStaffFreeTicket
END
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[cbm_spGeneralStaffFreeTicket]
(
	@member_id nvarchar(100),
	@recognition_id integer,
	@item_id integer,
	@movie_id integer,
	@quantity_requested integer,
	@cinema_id integer,
	@TransNo integer,
	@formatsession_time NVARCHAR(40),
	@card_number nvarchar(100),
	@language nvarchar(100))
AS

BEGIN

	-- Prevent any shared locks being created during execution of SP
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE 
	@Result				BIT,
	@strResponse		NVARCHAR(1000),
	@dayLimit			int,
	@dayFact			int,
	@orderDayFact		int,
	@sessionLimit		int,
	@sessionFact		int,
	@orderSessionFact	int,
	@maxAdmitDay		int,
	@strDate			nvarchar(10),
	@strLocalDate		nvarchar(10),
	@restAdmit			int=0,
	@intNewReleaseDurationDays int

	SET @strResponse = ''
	SET @Result = 1

	--Make sure the member is qualified to take this recognition
	IF NOT EXISTS (	SELECT 1 FROM cognetic_members_membershipRecognition
					WHERE membershipRecognition_recognitionid = @recognition_id
						AND membershipRecognition_membershipid = @member_id
						AND membershipRecognition_status = 'Qualified'
						-- doesn't allow next month session booking. #824 -  this feature disabled from 09-2017
						-- AND @formatsession_time between membershipRecognition_nextQualifyingDate AND r.membershipRecognition_expiryDate
						AND membershipRecognition_isDisqualified = 0)
	BEGIN
		SET @Result = 0
		SET @strResponse = dbo.translate(@language, 'Member not qualified to take this recognition.')
		GOTO RETURNLABEL
	END

	DECLARE @totalAvailableRecognitions INT = 0

	SELECT @totalAvailableRecognitions = SUM(membershipRecognition_totalEarned - membershipRecognition_numberOfRedemptions)
	FROM cognetic_members_membershipRecognition
	WHERE membershipRecognition_recognitionid = @recognition_id
		AND membershipRecognition_membershipid = @member_id
		AND membershipRecognition_status = 'Qualified'
		-- TODO: recognition must be expired in time, next row must be rewrited
		AND @formatsession_time between membershipRecognition_nextQualifyingDate AND DATEADD(DAY,1,membershipRecognition_expiryDate) ---r.membershipRecognition_expiryDate

	--Make sure the recognition is available
	IF @totalAvailableRecognitions <= 0
	BEGIN
		SET @Result = 0
		SET @strResponse = dbo.translate(@language, 'All of the recognitions allowed have been redeemed.')
		GOTO RETURNLABEL
	END

	-- Ensure the request won't exceed the number of available recognitions
	IF @totalAvailableRecognitions - @quantity_requested < 0
	BEGIN
		SET @Result = 0
		SET @strResponse = dbo.translate(@language, 'The number of recognitions requested exceeds the number available for redemption.')
		GOTO RETURNLABEL
	END

	--- get limits
	select 
			@intNewReleaseDurationDays=COALESCE(c.Film_intNewReleaseDurationDays,0),
			@strDate=convert(nvarchar(10),c.dNoFreeTixDate,120),
			@strLocalDate=convert(nvarchar(10),c.dNoFreeTixDate,104),
			@dayLimit=ISNULL(c.DayAdmit,0), 
			@sessionLimit=ISNULL(c.SessionAdmit,0), 
			@maxAdmitDay=ISNULL(c.MaxAdmitDay,0) 
	from cbm_tblFilm c
		JOIN cognetic_rules_movie m on c.Film_strHOFilmCode=m.movie_code 
	where 
		c.Film_strStatus='A' 
		AND m.movie_id=@movie_id

	-- Check 'No Free Tickets Until'
	IF NOT EXISTS (
	SELECT m.movie_id 
	FROM cbm_tblFilm c
		JOIN cognetic_rules_movie m ON m.movie_code=c.Film_strHOFilmCode
	WHERE 
		c.Film_strStatus='A' 
		AND m.movie_id=@movie_id
		AND c.dNoFreeTixDate <= @formatsession_time
	)	
	BEGIN
		SET @Result = 0
		SET @strResponse = dbo.translate(@language, 'Free tickets for this film are disable till') + ' ' + @strLocalDate
		GOTO RETURNLABEL
	END

	-- Check 'New Release Duration (days)'
	IF @intNewReleaseDurationDays = 0
	BEGIN
		SET @Result = 0
		SET @strResponse = dbo.translate(@language, 'Error: New Release Duration not define for this film')
		GOTO RETURNLABEL
	END

	IF NOT EXISTS (
		SELECT m.movie_id 
		FROM cbm_tblFilm c
			JOIN cognetic_rules_movie m ON m.movie_code=c.Film_strHOFilmCode
		WHERE 
			c.Film_strStatus='A' 
			AND DATEADD(day, @intNewReleaseDurationDays, c.Film_dtmOpeningDate) <= @formatsession_time
			AND m.movie_id=@movie_id
	)
	BEGIN
		SET @Result = 0
		SET @strResponse = dbo.translate(@language,'Free tickets are disable during new release period')
		GOTO RETURNLABEL
	END

	SELECT @strDate = convert(nvarchar(10),@formatsession_time,120)

	IF (@dayLimit+@sessionLimit) = 0
	BEGIN
		SET @Result = 0
		SET @strResponse = dbo.translate(@language,'Restriction isnt set for this movie. Free tickets are disable')
		GOTO RETURNLABEL
	END

	--- take into account rest from prev day
	SELECT @restAdmit=admit FROM cbm_tblPrevDayRest
	WHERE cinemaId=@cinema_id AND filmId=@movie_id AND hireDate=@strDate

	--- take into account max admit per day
	IF @restAdmit >0
	BEGIN 
		IF @dayLimit + @restAdmit >  @maxAdmitDay
		BEGIN
			SET @dayLimit = @maxAdmitDay
		END
		ELSE
			SET @dayLimit = @dayLimit + @restAdmit
	END

	--- get identifiers from setting
	DECLARE @freeTicketsIdentifierList	NVARCHAR(1000),
			@freeTicketsRecognitionIdentifierList	NVARCHAR(1000)
	
	SELECT @freeTicketsIdentifierList=setting_value
	FROM cognetic_setup_setting
	WHERE setting_name = 'FreeTicketsIdentifierList'

	SELECT @freeTicketsRecognitionIdentifierList=setting_value
	FROM cognetic_setup_setting
	WHERE setting_name = 'FreeTicketsRecognitionIdentifierList'

	EXEC	@dayFact = cbm_spFreeTicketIssuedQtyPerDay
			@movie_id,
			@strDate,
			@cinema_id,
			@freeTicketsIdentifierList
			

	EXEC	@orderDayFact = cbm_spFreeTicketOrderingQtyPerDay
			@movie_id,
			@strDate,
			@cinema_id,
			@freeTicketsRecognitionIdentifierList
				

	IF  (@dayLimit > 0) AND (@dayFact + @orderDayFact + @quantity_requested > @dayLimit)
	BEGIN
		SET @Result = 0
		SET @strResponse  = dbo.translate(@language, 'No more free tickets available for this day')+':'+
			dbo.translate(@language, 'Soled') + '-'+cast(@dayFact as nvarchar)+'|'+
			dbo.translate(@language, 'Ordered') + '-'+cast(@orderDayFact as nvarchar)+'|'+
			dbo.translate(@language, 'Your ordered') + '-'+cast(@quantity_requested as nvarchar)+'|'+
			dbo.translate(@language, 'Restriction') + '-'+cast(@dayLimit as nvarchar)
			GOTO RETURNLABEL
	END

	EXEC	@sessionFact = cbm_spFreeTicketIssuedQtyPerSession
			@film = @movie_id,
			@sessiontime = @formatsession_time,
			@cinema = @cinema_id,
			@freeTicketsIdentifierList = @freeTicketsIdentifierList
					
		
	EXEC	@orderSessionFact = cbm_spFreeTicketOrderingQtyPerSession
			@film = @movie_id,
			@sessiontime = @formatsession_time,
			@cinema = @cinema_id,
			@freeTicketsRecognitionIdentifierList = @freeTicketsRecognitionIdentifierList
					
	IF (@sessionLimit>0) AND (@sessionFact + @orderSessionFact + @quantity_requested > @sessionLimit)
	BEGIN
		SET @Result = 0
		SET @strResponse = dbo.translate(@language,'No more free tickets available for this session')+':'+
			dbo.translate(@language, 'Soled') + '-'+cast(@sessionFact as nvarchar)+'|'+
			dbo.translate(@language, 'Ordered') + '-'+cast(@orderSessionFact as nvarchar)+'|'+
			dbo.translate(@language, 'Your ordered') + '-'+cast(@quantity_requested as nvarchar)+'|'+
			dbo.translate(@language, 'Restriction') + '-'+cast(@sessionLimit as nvarchar)
			GOTO RETURNLABEL
	END

--OUTPUT----------------------------------------------
	
	RETURNLABEL:
	IF @Result= 0
	BEGIN
		--- SET @strResponse = dbo.translate(@language, @strResponse)
		INSERT INTO #tempResultTable (Result, ResultDesc) VALUES (@Result, @strResponse)
	END

	SELECT @Result

END	

GO

GRANT  EXECUTE  ON [dbo].[cbm_spGeneralStaffFreeTicket]   TO PUBLIC
GO