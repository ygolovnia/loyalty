USE [VISTALOYALTY]
GO

/****** Object:  StoredProcedure [dbo].[cbm_spHOStaffFreeTicket_v2]    Script Date: 02.07.2016 17:03:53 ******/

IF EXISTS (SELECT 1 FROM sysobjects where id = object_id(N'dbo.cbm_spHOStaffFreeTicket_v2') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
	DROP PROCEDURE dbo.cbm_spHOStaffFreeTicket_v2
END
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE dbo.cbm_spHOStaffFreeTicket_v2
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

	--- check availability of recognition
	DECLARE @totalAvailableRecognitions INT = 0
	SELECT @totalAvailableRecognitions = ISNULL(SUM(r.membershipRecognition_totalEarned - r.membershipRecognition_numberOfRedemptions),0)
	FROM cognetic_members_membershipRecognition r
	WHERE r.membershipRecognition_recognitionid = @recognition_id
		AND r.membershipRecognition_membershipid = @member_id
		AND r.membershipRecognition_status='Qualified'
		AND GETDATE() between r.membershipRecognition_nextQualifyingDate AND r.membershipRecognition_expiryDate
	--Make sure the quantity available is greater than the quantity redeemed
	IF @totalAvailableRecognitions <= 0
	BEGIN
		SET @Result = 0
		SET @strResponse = dbo.translate(@language, 'All of the recognitions allowed have been redeemed.')
	END
	ELSE
	BEGIN

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

		SELECT @strDate = convert(nvarchar(10),@formatsession_time,120)

		IF (@dayLimit+@sessionLimit) = 0
		BEGIN
			SET @Result = 0
			SET @strResponse = dbo.translate(@language,'Restriction isnt set for this movie. Free tickets are disable')
		END
		ELSE
		BEGIN
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
			END
			ELSE
			BEGIN
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
				END
			END
		END
	END
--OUTPUT----------------------------------------------
	IF @Result= 0
	BEGIN
		--- SET @strResponse = dbo.translate(@language, @strResponse)
		INSERT INTO #tempResultTable (Result, ResultDesc) VALUES (@Result, @strResponse)
	END

	SELECT @Result

END	

GO

GRANT  EXECUTE  ON dbo.cbm_spHOStaffFreeTicket_v2 TO PUBLIC


GO

