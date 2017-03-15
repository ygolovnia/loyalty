IF EXISTS (SELECT 1 FROM sysobjects where id = object_id(N'dbo.cbm_spFreeTicketIssuedQtyPerSession') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
	DROP PROCEDURE dbo.cbm_spFreeTicketIssuedQtyPerSession
END
GO

CREATE PROCEDURE [dbo].[cbm_spFreeTicketIssuedQtyPerSession](
@film			int,
@sessiontime	datetime,
@cinema			int,
@freeTicketsIdentifierList nvarchar(1000)
)

AS

BEGIN
	-- Prevent any shared locks being created during execution of SP
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @qty int,
			@sql nvarchar(1000)

	SET @sql = N'
	select 
		@qty = COALESCE(sum(cast(r.transactionRecognition_numberOfRedemptions as int)),0)
	from 
		cognetic_data_transactionRecognition r 
	where 
		r.transactionRecognition_transactionid in 
		(
			select 
				t.transaction_id 
			from 
				cognetic_data_transaction t 
			where 
				t.transaction_POStransactionid in 
				(
					select t.transaction_POStransactionid
					from 
						cognetic_data_transaction t
						join cognetic_data_transactionItem i on t.transaction_id=i.transactionItem_transactionid
					where 
						t.transaction_workstationID is not NULL
						and t.transaction_cinemaOperator is not NULL
						and t.transaction_isValidateRecognition is NULL --- =1 for validate step
						and t.transaction_complexid=@cinema
						and i.transactionItem_movieid=@film
						and i.transactionItem_itemid IN('+ @freeTicketsIdentifierList +')
						and i.transactionItem_sessionTime = @sessiontime
						group by t.transaction_POStransactionid
				)
		)'

	exec sp_executesql @sql, N'@cinema int, @film int, @sessiontime DATETIME, @qty int output', @cinema, @film, @sessiontime, @qty output


	return @qty
END
GO

GRANT  EXECUTE  ON [dbo].[cbm_spFreeTicketIssuedQtyPerSession]   TO PUBLIC
GO