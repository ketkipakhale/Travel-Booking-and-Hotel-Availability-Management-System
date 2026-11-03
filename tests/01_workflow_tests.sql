USE TravelBookingDB;
GO
SET NOCOUNT ON;
DECLARE @GuestID int,@ReservationID int,@OverlapReservationID int,@Key varchar(80),@BookingCode varchar(40),
        @OverlapKey varchar(80),@BusyKey varchar(80),@DateKey varchar(80),@CapacityKey varchar(80),
        @PayKey varchar(80),@RefundKey varchar(80),@ExtraRefundKey varchar(80);
SET @Key='test-'+CONVERT(varchar(36),NEWID());
SET @BookingCode='test-'+CONVERT(varchar(36),NEWID());
SET @OverlapKey=@Key+'-overlap'; SET @BusyKey=@Key+'-busy'; SET @DateKey=@Key+'-dates';
SET @CapacityKey=@Key+'-capacity'; SET @PayKey=@Key+'-pay'; SET @RefundKey=@Key+'-refund';
SET @ExtraRefundKey=@Key+'-refund-extra';

INSERT dbo.Guests(FirstName,LastName,Email) VALUES(N'Test',N'Guest',@BookingCode+N'@example.test');
SET @GuestID=CONVERT(int,SCOPE_IDENTITY());

/* Normal multi-room booking and room addition. */
EXEC dbo.usp_CreateReservation @GuestID=@GuestID,@PropertyID=3,
    @CheckInDate='2027-05-10',@CheckOutDate='2027-05-13',@GuestCount=2,
    @RoomIDs=N'15',@IdempotencyKey=@Key,@ReservationID=@ReservationID OUTPUT;
EXEC dbo.usp_AddRoomsToReservation @ReservationID=@ReservationID,@RoomIDs=N'13';
PRINT 'PASS: created a reservation and added another room.';

/* Overlapping active reservation must be rejected. */
BEGIN TRY
    EXEC dbo.usp_CreateReservation @GuestID=@GuestID,@PropertyID=3,
      @CheckInDate='2027-05-11',@CheckOutDate='2027-05-14',@GuestCount=2,
      @RoomIDs=N'15',@IdempotencyKey=@OverlapKey,@ReservationID=@OverlapReservationID OUTPUT;
    THROW 51990,'Expected overlapping booking to fail.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()=51990 THROW;
    PRINT 'PASS: overlapping booking was rejected.';
END CATCH;

/* Seeded room 3 is occupied on these dates. */
BEGIN TRY
    EXEC dbo.usp_CreateReservation @GuestID=@GuestID,@PropertyID=1,
      @CheckInDate='2026-12-11',@CheckOutDate='2026-12-12',@GuestCount=2,
      @RoomIDs=N'3',@IdempotencyKey=@BusyKey,@ReservationID=@OverlapReservationID OUTPUT;
    THROW 51990,'Expected unavailable room to fail.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()=51990 THROW;
    PRINT 'PASS: unavailable room was rejected.';
END CATCH;

/* Invalid dates and too many guests for selected room type. */
BEGIN TRY
    EXEC dbo.usp_CreateReservation @GuestID=@GuestID,@PropertyID=3,
      @CheckInDate='2027-06-15',@CheckOutDate='2027-06-15',@GuestCount=2,
      @RoomIDs=N'12',@IdempotencyKey=@DateKey,@ReservationID=@OverlapReservationID OUTPUT;
    THROW 51990,'Expected invalid date range to fail.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()=51990 THROW;
    PRINT 'PASS: invalid date range was rejected.';
END CATCH;

BEGIN TRY
    EXEC dbo.usp_CreateReservation @GuestID=@GuestID,@PropertyID=3,
      @CheckInDate='2027-06-15',@CheckOutDate='2027-06-16',@GuestCount=3,
      @RoomIDs=N'12',@IdempotencyKey=@CapacityKey,@ReservationID=@OverlapReservationID OUTPUT;
    THROW 51990,'Expected over-capacity booking to fail.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()=51990 THROW;
    PRINT 'PASS: over-capacity booking was rejected.';
END CATCH;

/* Date changes must also preserve inventory safety. */
EXEC dbo.usp_ModifyReservationDates @ReservationID=@ReservationID,
    @CheckInDate='2027-05-12',@CheckOutDate='2027-05-15';
PRINT 'PASS: reservation dates were modified.';

/* Payment, duplicate payment key, cancellation, and refund amount validation. */
EXEC dbo.usp_RecordPayment @ReservationID=@ReservationID,@Amount=250.00,@CurrencyCode='USD',
    @IdempotencyKey=@PayKey,@PaymentNote=N'Test payment';
BEGIN TRY
    EXEC dbo.usp_RecordPayment @ReservationID=@ReservationID,@Amount=250.00,@CurrencyCode='USD',
        @IdempotencyKey=@PayKey,@PaymentNote=N'Duplicate test payment';
    THROW 51990,'Expected duplicate payment key to fail.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()=51990 THROW;
    IF XACT_STATE()<>0 ROLLBACK;
    PRINT 'PASS: duplicate payment key was rejected.';
END CATCH;

EXEC dbo.usp_CancelReservation @ReservationID=@ReservationID,@Reason=N'Test cancellation',@CancelledBy=N'Test suite';
EXEC dbo.usp_ProcessRefund @ReservationID=@ReservationID,@Amount=250.00,@CurrencyCode='USD',
    @IdempotencyKey=@RefundKey,@PaymentNote=N'Test full refund';
PRINT 'PASS: cancellation and full refund were recorded.';

BEGIN TRY
    EXEC dbo.usp_ProcessRefund @ReservationID=@ReservationID,@Amount=1.00,@CurrencyCode='USD',
        @IdempotencyKey=@ExtraRefundKey,@PaymentNote=N'Excess refund test';
    THROW 51990,'Expected excess refund to fail.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()=51990 THROW;
    IF XACT_STATE()<>0 ROLLBACK;
    PRINT 'PASS: refund exceeding amount paid was rejected.';
END CATCH;

/* Remove all test records so the script can be rerun cleanly. */
DELETE FROM dbo.Payments WHERE ReservationID=@ReservationID;
DELETE FROM dbo.Cancellations WHERE ReservationID=@ReservationID;
DELETE FROM dbo.ReservationStatusHistory WHERE ReservationID=@ReservationID;
DELETE FROM dbo.ReservationRooms WHERE ReservationID=@ReservationID;
DELETE FROM dbo.Reservations WHERE ReservationID=@ReservationID;
DELETE FROM dbo.Guests WHERE GuestID=@GuestID;
PRINT 'Test workflow completed; test rows removed.';
GO
