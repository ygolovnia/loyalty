IF EXISTS (SELECT 1 FROM sysobjects where id = object_id(N'dbo.cbm_spMoveRestAdmit') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
	DROP PROCEDURE dbo.cbm_spMoveRestAdmit
END
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[cbm_spMoveRestAdmit]
AS
BEGIN

	-- Prevent any shared locks being created during execution of SP
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	create table #films(movie_id int, DayAdmit int,cinema_id int)
	
	insert into #films
	select m.movie_id, m.DayAdmit, k.complex_id cinema_id
	from cognetic_campaigns_complex k,(
	SELECT m.movie_id, c.DayAdmit
	FROM  
		cbm_tblFilm c
		JOIN cognetic_rules_movie m ON m.movie_code=c.Film_strHOFilmCode
	WHERE 
		c.Film_strStatus='A' --- active
		AND c.isRestMove=1 AND c.DayAdmit>0 
		AND (c.filmHireEnd>GETDATE() OR c.filmHireEnd IS NULL)) m

	DECLARE	@movie_id int, @DayAdmit int, @cinema_id int, @strDate nvarchar(10),
			@dayFact int

	SELECT @strDate = convert(nvarchar(10), DATEADD(day, -1,GETDATE()), 120)
	
	--- get identifiers from setting
	DECLARE @freeTicketsIdentifierList	NVARCHAR(1000)
	
	SELECT @freeTicketsIdentifierList=setting_value
	FROM cognetic_setup_setting
	WHERE setting_name = 'FreeTicketsIdentifierList'
	
	WHILE EXISTS(SELECT * FROM #films)
	BEGIN
		SELECT TOP 1 @movie_id=movie_id, @DayAdmit=DayAdmit, @cinema_id=cinema_id FROM #films

		EXEC	@dayFact = cbm_spFreeTicketIssuedQtyPerDay
				@movie_id,
				@strDate,
				@cinema_id,
				@freeTicketsIdentifierList		
		
		IF @dayFact < @DayAdmit
		BEGIN
			INSERT INTO cbm_tblPrevDayRest (cinemaId, filmId, hireDate, admit)
			VALUES (@cinema_id, @movie_id, DATEADD(day,1,@strDate), @DayAdmit-@dayFact)
		END

		DELETE FROM #films WHERE movie_id=@movie_id AND DayAdmit=@DayAdmit AND cinema_id=@cinema_id
	END

END
GO

GRANT  EXECUTE  ON [dbo].[cbm_spMoveRestAdmit]   TO PUBLIC
GO