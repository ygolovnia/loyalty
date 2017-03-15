IF EXISTS (SELECT 1 FROM sysobjects where id = object_id(N'dbo.cbm_spFreeTicketOrderingQtyPerDay') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
	DROP PROCEDURE dbo.cbm_spFreeTicketOrderingQtyPerDay
END
GO

CREATE PROCEDURE [dbo].[cbm_spFreeTicketOrderingQtyPerDay](
@film		int,
@date		nvarchar(10),
@cinema		int,
@freeTicketsRecognitionIdentifierList	nvarchar(1000)
)

AS
BEGIN
	-- Prevent any shared locks being created during execution of SP
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @qty int = NULL,
			@sql nvarchar(1000)

	SET @sql = N'
		SELECT
		  @qty = COALESCE(SUM(CAST(r.transactionRecognition_numberOfRedemptions AS int)), 0)
		FROM cognetic_data_transaction t
		JOIN cognetic_data_transactionRecognition r
		  ON t.transaction_id = r.transactionRecognition_transactionid
		WHERE r.transactionRecognition_movieid = @film
		AND r.transactionRecognition_recogid IN (' + @freeTicketsRecognitionIdentifierList + ')
		AND CONVERT(nvarchar(10), r.transactionRecognition_sessionTime, 120) = @date
		AND t.transaction_complexid = @cinema
		AND t.transaction_workstationID IS NULL
		AND t.transaction_cinemaOperator IS NULL
		AND t.transaction_isValidateRecognition = 1
		AND t.transaction_POStransactionId NOT IN (
			SELECT
			  t.transaction_POStransactionId
			FROM cognetic_data_transaction t
			WHERE t.transaction_workstationID IS NOT NULL
			AND t.transaction_cinemaOperator IS NOT NULL
			AND t.transaction_isValidateRecognition IS NULL)'

	exec sp_executesql @sql, N'@cinema int, @film int, @date nvarchar(10), @qty int output', @cinema, @film, @date, @qty output

	return @qty
END
GO

GRANT  EXECUTE  ON [dbo].[cbm_spFreeTicketOrderingQtyPerDay]   TO PUBLIC
GO
