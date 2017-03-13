/**
* updated 01.07.2016
*/


USE [VISTALOYALTY]
GO

IF EXISTS (SELECT 1 FROM sysobjects where id = object_id(N'dbo.cbm_spFreeTicketIssuedQtyPerSession') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
	DROP PROCEDURE dbo.cbm_spFreeTicketIssuedQtyPerSession
END
GO

CREATE PROCEDURE [dbo].[cbm_spFreeTicketIssuedQtyPerSession](
@film			int,
@sessiontime	datetime,
@cinema			int
)

AS

BEGIN
	-- Prevent any shared locks being created during execution of SP
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @qty int,
			--- @itemId int = 1013 ---675 LAB

			@itemList nvarchar(50) = '1013|1018'
	
	/*DECLARE @list TABLE
	(
		itemId	NVARCHAR(10)
	)
	INSERT INTO @list
	EXEC dbo.SplitString	@StringInput	= @itemList,
							@Delimiter		= '|',
							@RemoveEmpty	= 1			
							*/
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
						and i.transactionItem_itemid IN(1013,1018)
						and i.transactionItem_sessionTime = @sessiontime
						group by t.transaction_POStransactionid
				)
		)

	return @qty
END

GO

GRANT  EXECUTE  ON [dbo].[cbm_spFreeTicketIssuedQtyPerSession]   TO PUBLIC

GO