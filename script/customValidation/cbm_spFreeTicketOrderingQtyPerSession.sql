/**
* updated 01.07.2016
*/


USE [VISTALOYALTY]
GO

IF EXISTS (SELECT 1 FROM sysobjects where id = object_id(N'dbo.cbm_spFreeTicketOrderingQtyPerSession') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
	DROP PROCEDURE dbo.cbm_spFreeTicketOrderingQtyPerSession
END
GO

CREATE PROCEDURE [dbo].[cbm_spFreeTicketOrderingQtyPerSession](
@film			int,
@sessiontime	datetime,
@cinema			int
)

AS
BEGIN
	-- Prevent any shared locks being created during execution of SP
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @qty int,
			@recogList nvarchar(50) = '1|2' --- 22 LAB

	/*DECLARE @list TABLE
	(
		recogId	NVARCHAR(10)
	)
	INSERT INTO @list
	EXEC dbo.SplitString	@StringInput	= @recogList,
							@Delimiter		= '|',
							@RemoveEmpty	= 1
	
	*/
	select @qty=COALESCE(sum(cast(r.transactionRecognition_numberOfRedemptions as int)),0)
	from cognetic_data_transaction t 
	join cognetic_data_transactionRecognition r on t.transaction_id=r.transactionRecognition_transactionid
	where 
	r.transactionRecognition_movieid=@film
---	and r.transactionRecognition_recogid IN (SELECT recogId FROM @list)                  ----=@recogId ----!!!!!!
	and r.transactionRecognition_recogid IN (1,2)                  ----=@recogId ----!!!!!!
	and r.transactionRecognition_sessionTime=@sessiontime
	and t.transaction_complexid=@cinema
	and t.transaction_workstationID is NULL
	and t.transaction_cinemaOperator is NULL
	and t.transaction_isValidateRecognition=1
	and  t.transaction_POStransactionId not in 
	(select t.transaction_POStransactionId 
	from cognetic_data_transaction t 
	where 
	t.transaction_workstationID is NOT NULL
	and t.transaction_cinemaOperator is NOT NULL
	and t.transaction_isValidateRecognition is NULL )

	return @qty
END

GO

GRANT  EXECUTE  ON [dbo].[cbm_spFreeTicketOrderingQtyPerSession]   TO PUBLIC

GO