IF EXISTS (SELECT 1 FROM sysobjects where id = object_id(N'dbo.cbm_spFreeTicketOrderingQtyPerSession') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
	DROP PROCEDURE dbo.cbm_spFreeTicketOrderingQtyPerSession
END
GO

CREATE PROCEDURE [dbo].[cbm_spFreeTicketOrderingQtyPerSession](
@film			int,
@sessiontime	datetime,
@cinema			int,
@freeTicketsRecognitionIdentifierList	nvarchar(1000)
)

AS
BEGIN
	-- Prevent any shared locks being created during execution of SP
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @qty int,
			@sql nvarchar(1000)

	SET @sql = N'
	select @qty=COALESCE(sum(cast(r.transactionRecognition_numberOfRedemptions as int)),0)
	from cognetic_data_transaction t 
	join cognetic_data_transactionRecognition r on t.transaction_id=r.transactionRecognition_transactionid
	where 
	r.transactionRecognition_movieid=@film
	and r.transactionRecognition_recogid IN (' + @freeTicketsRecognitionIdentifierList + ')
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
	and t.transaction_isValidateRecognition is NULL )'

	exec sp_executesql @sql, N'@cinema int, @film int, @sessiontime DATETIME, @qty int output', @cinema, @film, @sessiontime, @qty output

	return @qty
END
GO

GRANT  EXECUTE  ON [dbo].[cbm_spFreeTicketOrderingQtyPerSession]   TO PUBLIC
GO