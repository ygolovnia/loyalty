IF EXISTS (SELECT 1 FROM sysobjects where id = object_id(N'dbo.cbm_spFreeTicketIssuedQtyPerDay') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
	DROP PROCEDURE dbo.cbm_spFreeTicketIssuedQtyPerDay
END
GO

CREATE PROCEDURE [dbo].[cbm_spFreeTicketIssuedQtyPerDay](
@film		int,
@date		nvarchar(10),
@cinema		int,
@freeTicketsIdentifierList nvarchar(1000)
)
AS
BEGIN 
	-- Prevent any shared locks being created during execution of SP
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @qty int,
			@sql nvarchar(1000)

	SET @sql = 
N'select @qty = COALESCE(sum(cast(r.transactionRecognition_numberOfRedemptions as int)),0)
from cognetic_data_transactionRecognition r 
where r.transactionRecognition_transactionid in 
(
select t.transaction_id
from cognetic_data_transaction t
where t.transaction_POStransactionid in
(
select t.transaction_POStransactionid
from cognetic_data_transaction t
join cognetic_data_transactionItem i on t.transaction_id=i.transactionItem_transactionid
where
t.transaction_workstationID is not NULL
and t.transaction_cinemaOperator is not NULL
and t.transaction_isValidateRecognition is NULL
and t.transaction_complexid=@cinema
and i.transactionItem_movieid=@film
and i.transactionItem_itemid IN('+ @freeTicketsIdentifierList +')
and convert(nvarchar(10),i.transactionItem_sessionTime,120)=@date
group by t.transaction_POStransactionid
)
)'
	
	exec sp_executesql @sql, N'@cinema int, @film int, @date nvarchar(10), @qty int output', @cinema, @film, @date, @qty output
			
	return @qty
END
GO

GRANT  EXECUTE  ON [dbo].[cbm_spFreeTicketIssuedQtyPerDay]   TO PUBLIC
GO