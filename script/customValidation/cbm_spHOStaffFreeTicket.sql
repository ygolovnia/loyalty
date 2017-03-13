/****** Object:  StoredProcedure [dbo].[cbm_spHOStaffFreeTicket]    Script Date: 02.07.2016 17:03:53 ******/

IF EXISTS (SELECT 1 FROM sysobjects where id = object_id(N'dbo.cbm_spHOStaffFreeTicket') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
	DROP PROCEDURE dbo.cbm_spHOStaffFreeTicket
END
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE dbo.cbm_spHOStaffFreeTicket
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
	@restAdmit			int=0,
	@intNewReleaseDurationDays int

	SET @strResponse = ''
	SET @Result = 1

	--Make sure the member is qualified to take this recognition
	IF NOT EXISTS (	SELECT 1 FROM cognetic_members_membershipRecognition
					WHERE membershipRecognition_recognitionid = @recognition_id
						AND membershipRecognition_membershipid = @member_id
						AND membershipRecognition_status = 'Qualified'
						-- TODO: recognition must be expired in time, next row must be rewrited
						AND @formatsession_time between membershipRecognition_nextQualifyingDate AND DATEADD(DAY,1,membershipRecognition_expiryDate) ---r.membershipRecognition_expiryDate
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
			@dayLimit=ISNULL(c.DayAdmit,0), 
			@sessionLimit=ISNULL(c.SessionAdmit,0), 
			@maxAdmitDay=ISNULL(c.MaxAdmitDay,0) 
	from cbm_tblFilm c
		JOIN cognetic_rules_movie m on c.Film_strHOFilmCode=m.movie_code 
	where 
		c.Film_strStatus='A' 
		AND m.movie_id=@movie_id

	SELECT @strDate = convert(nvarchar(10), @formatsession_time, 120)

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

	EXEC	@dayFact = cbm_spFreeTicketIssuedQtyPerDay
			@movie_id,
			@strDate,
			@cinema_id
			
	EXEC	@orderDayFact = cbm_spFreeTicketOrderingQtyPerDay
			@movie_id,
			@strDate,
			@cinema_id
				
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
			@cinema = @cinema_id
					
		
	EXEC	@orderSessionFact = cbm_spFreeTicketOrderingQtyPerSession
			@film = @movie_id,
			@sessiontime = @formatsession_time,
			@cinema = @cinema_id
					
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
		INSERT INTO #tempResultTable (Result, ResultDesc) VALUES (@Result, @strResponse)
	END

	SELECT @Result

END	

GO

GRANT  EXECUTE  ON dbo.cbm_spHOStaffFreeTicket TO PUBLIC
GO
