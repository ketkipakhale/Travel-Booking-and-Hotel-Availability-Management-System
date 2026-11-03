USE TravelBookingDB;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SearchAvailability
    @PropertyID int,
    @CheckInDate date,
    @CheckOutDate date,
    @GuestCount tinyint
AS
BEGIN
    SET NOCOUNT ON;
    IF @CheckInDate IS NULL OR @CheckOutDate IS NULL OR @CheckOutDate <= @CheckInDate
        THROW 51001, 'Check-out must be later than check-in.', 1;
    IF @GuestCount IS NULL OR @GuestCount < 1
        THROW 51002, 'Guest count must be at least one.', 1;
    SELECT r.RoomID, r.RoomNumber, rt.TypeName AS RoomType, rt.MaxOccupancy,
           rt.BaseNightlyRate AS NightlyRate, p.PropertyName
    FROM dbo.Rooms AS r
    JOIN dbo.RoomTypes AS rt ON rt.PropertyID = r.PropertyID AND rt.RoomTypeID = r.RoomTypeID
    JOIN dbo.Properties AS p ON p.PropertyID = r.PropertyID
    WHERE r.PropertyID = @PropertyID AND r.IsActive = 1 AND rt.IsActive = 1 AND p.IsActive = 1
      AND rt.MaxOccupancy >= @GuestCount
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.ReservationRooms AS rr
          JOIN dbo.Reservations AS b ON b.ReservationID = rr.ReservationID
          WHERE rr.RoomID = r.RoomID
            AND b.Status IN ('Confirmed','CheckedIn')
            AND b.CheckInDate < @CheckOutDate AND b.CheckOutDate > @CheckInDate
      )
    ORDER BY rt.BaseNightlyRate, r.RoomNumber;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CreateReservation
    @GuestID int,
    @PropertyID int,
    @CheckInDate date,
    @CheckOutDate date,
    @GuestCount tinyint,
    @RoomIDs nvarchar(400),
    @IdempotencyKey varchar(80),
    @ReservationID int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @CheckInDate IS NULL OR @CheckOutDate IS NULL OR @CheckOutDate <= @CheckInDate
        THROW 51001, 'Check-out must be later than check-in.', 1;
    IF @GuestCount IS NULL OR @GuestCount NOT BETWEEN 1 AND 20
        THROW 51002, 'Guest count must be between 1 and 20.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Guests WHERE GuestID = @GuestID)
        THROW 51003, 'Guest does not exist.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Properties WHERE PropertyID = @PropertyID AND IsActive = 1)
        THROW 51004, 'Property does not exist or is inactive.', 1;
    IF NULLIF(LTRIM(RTRIM(@IdempotencyKey)), '') IS NULL
        THROW 51005, 'Idempotency key is required.', 1;

    DECLARE @SelectedRooms table (RoomID int PRIMARY KEY);
    INSERT @SelectedRooms(RoomID)
    SELECT DISTINCT TRY_CONVERT(int, LTRIM(RTRIM(value)))
    FROM STRING_SPLIT(COALESCE(@RoomIDs,N''), N',')
    WHERE TRY_CONVERT(int, LTRIM(RTRIM(value))) IS NOT NULL;
    IF (SELECT COUNT(*) FROM @SelectedRooms) = 0 OR EXISTS (
        SELECT 1 FROM STRING_SPLIT(COALESCE(@RoomIDs,N''), N',')
        WHERE NULLIF(LTRIM(RTRIM(value)),N'') IS NOT NULL AND TRY_CONVERT(int,LTRIM(RTRIM(value))) IS NULL)
        THROW 51006, 'Provide a comma-separated list of valid room IDs.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Locked int;
        /* Lock the selected room inventory in ascending ID order before checking overlaps. */
        DECLARE room_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT RoomID FROM @SelectedRooms ORDER BY RoomID;
        OPEN room_cursor;
        FETCH NEXT FROM room_cursor INTO @Locked;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.Rooms WITH (UPDLOCK,HOLDLOCK) WHERE RoomID = @Locked)
                THROW 51007, 'One or more selected rooms do not exist.', 1;
            FETCH NEXT FROM room_cursor INTO @Locked;
        END;
        CLOSE room_cursor;
        DEALLOCATE room_cursor;

        IF EXISTS (
            SELECT 1 FROM @SelectedRooms s
            LEFT JOIN dbo.Rooms r ON r.RoomID = s.RoomID
            LEFT JOIN dbo.RoomTypes rt ON rt.PropertyID = r.PropertyID AND rt.RoomTypeID = r.RoomTypeID
            WHERE r.RoomID IS NULL OR r.PropertyID <> @PropertyID OR r.IsActive = 0 OR rt.IsActive = 0 OR rt.MaxOccupancy < @GuestCount)
            THROW 51008, 'A selected room is inactive, belongs to another property, or cannot fit the party.', 1;
        IF EXISTS (
            SELECT 1 FROM dbo.ReservationRooms rr
            JOIN @SelectedRooms s ON s.RoomID = rr.RoomID
            JOIN dbo.Reservations b ON b.ReservationID = rr.ReservationID
            WHERE b.Status IN ('Confirmed','CheckedIn')
              AND b.CheckInDate < @CheckOutDate AND b.CheckOutDate > @CheckInDate)
            THROW 51009, 'One or more selected rooms are unavailable for those dates.', 1;

        DECLARE @Code char(10) = UPPER(LEFT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),10));
        INSERT dbo.Reservations (ConfirmationCode,GuestID,PropertyID,CheckInDate,CheckOutDate,GuestCount,Status)
        VALUES (@Code,@GuestID,@PropertyID,@CheckInDate,@CheckOutDate,@GuestCount,'Confirmed');
        SET @ReservationID = CONVERT(int,SCOPE_IDENTITY());
        INSERT dbo.ReservationRooms (ReservationID,RoomID,NightlyRate)
        SELECT @ReservationID,r.RoomID,rt.BaseNightlyRate
        FROM @SelectedRooms s JOIN dbo.Rooms r ON r.RoomID=s.RoomID
        JOIN dbo.RoomTypes rt ON rt.PropertyID=r.PropertyID AND rt.RoomTypeID=r.RoomTypeID;
        INSERT dbo.ReservationStatusHistory (ReservationID,OldStatus,NewStatus,ChangedBy,ChangeNote)
        VALUES (@ReservationID,NULL,'Confirmed',SUSER_SNAME(),N'Reservation created');
        COMMIT TRANSACTION;
        SELECT @ReservationID AS ReservationID, @Code AS ConfirmationCode;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local','room_cursor') >= 0 CLOSE room_cursor;
        IF CURSOR_STATUS('local','room_cursor') > -3 DEALLOCATE room_cursor;
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AddRoomsToReservation
    @ReservationID int,
    @RoomIDs nvarchar(400)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @Selected table(RoomID int PRIMARY KEY);
    INSERT @Selected SELECT DISTINCT TRY_CONVERT(int,LTRIM(RTRIM(value))) FROM STRING_SPLIT(COALESCE(@RoomIDs,N''),N',')
      WHERE TRY_CONVERT(int,LTRIM(RTRIM(value))) IS NOT NULL;
    IF NOT EXISTS(SELECT 1 FROM @Selected) THROW 51006,'Provide valid room IDs.',1;
    BEGIN TRY
      BEGIN TRANSACTION;
      DECLARE @PropertyID int,@In date,@Out date,@Guests tinyint,@Status varchar(12),@Room int;
      DECLARE add_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT RoomID FROM @Selected ORDER BY RoomID;
      OPEN add_cursor; FETCH NEXT FROM add_cursor INTO @Room;
      WHILE @@FETCH_STATUS=0
      BEGIN
        IF NOT EXISTS(SELECT 1 FROM dbo.Rooms WITH(UPDLOCK,HOLDLOCK) WHERE RoomID=@Room) THROW 51007,'A selected room does not exist.',1;
        FETCH NEXT FROM add_cursor INTO @Room;
      END;
      CLOSE add_cursor; DEALLOCATE add_cursor;
      SELECT @PropertyID=PropertyID,@In=CheckInDate,@Out=CheckOutDate,@Guests=GuestCount,@Status=Status
      FROM dbo.Reservations WITH (UPDLOCK,HOLDLOCK) WHERE ReservationID=@ReservationID;
      IF @PropertyID IS NULL THROW 51010,'Reservation does not exist.',1;
      IF @Status <> 'Confirmed' THROW 51011,'Only confirmed reservations can be changed.',1;
      IF EXISTS(SELECT 1 FROM @Selected s LEFT JOIN dbo.Rooms r ON r.RoomID=s.RoomID
        LEFT JOIN dbo.RoomTypes t ON t.PropertyID=r.PropertyID AND t.RoomTypeID=r.RoomTypeID
        WHERE r.PropertyID<>@PropertyID OR r.IsActive=0 OR t.IsActive=0 OR t.MaxOccupancy<@Guests OR EXISTS
          (SELECT 1 FROM dbo.ReservationRooms x WHERE x.ReservationID=@ReservationID AND x.RoomID=s.RoomID))
        THROW 51008,'A room is invalid for this reservation or is already attached.',1;
      IF EXISTS(SELECT 1 FROM dbo.ReservationRooms x JOIN @Selected s ON s.RoomID=x.RoomID
        JOIN dbo.Reservations b ON b.ReservationID=x.ReservationID
        WHERE b.Status IN('Confirmed','CheckedIn') AND b.CheckInDate<@Out AND b.CheckOutDate>@In)
        THROW 51009,'One or more selected rooms are unavailable for those dates.',1;
      INSERT dbo.ReservationRooms(ReservationID,RoomID,NightlyRate)
      SELECT @ReservationID,r.RoomID,t.BaseNightlyRate FROM @Selected s JOIN dbo.Rooms r ON r.RoomID=s.RoomID
        JOIN dbo.RoomTypes t ON t.PropertyID=r.PropertyID AND t.RoomTypeID=r.RoomTypeID;
      UPDATE dbo.Reservations SET UpdatedAt=SYSUTCDATETIME() WHERE ReservationID=@ReservationID;
      COMMIT;
    END TRY
    BEGIN CATCH
      IF CURSOR_STATUS('local','add_cursor')>=0 CLOSE add_cursor;
      IF CURSOR_STATUS('local','add_cursor')>-3 DEALLOCATE add_cursor;
      IF XACT_STATE()<>0 ROLLBACK;
      THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RecordPayment
    @ReservationID int,
    @Amount decimal(10,2),
    @CurrencyCode char(3),
    @IdempotencyKey varchar(80),
    @PaymentNote nvarchar(250)=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @Amount IS NULL OR @Amount<=0 THROW 51012,'Payment amount must be positive.',1;
    IF @CurrencyCode IS NULL OR @CurrencyCode NOT LIKE '[A-Z][A-Z][A-Z]' THROW 51013,'Currency must be a three-letter uppercase code.',1;
    IF NULLIF(LTRIM(RTRIM(@IdempotencyKey)),'') IS NULL THROW 51005,'Idempotency key is required.',1;
    BEGIN TRANSACTION;
    IF NOT EXISTS(SELECT 1 FROM dbo.Reservations WITH(UPDLOCK,HOLDLOCK) WHERE ReservationID=@ReservationID AND Status IN('Confirmed','CheckedIn'))
    BEGIN ROLLBACK; THROW 51014,'Payment requires an existing confirmed or checked-in reservation.',1; END;
    INSERT dbo.Payments(ReservationID,PaymentType,Amount,CurrencyCode,IdempotencyKey,PaymentNote)
    VALUES(@ReservationID,'Charge',@Amount,@CurrencyCode,@IdempotencyKey,@PaymentNote);
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ModifyReservationDates
    @ReservationID int,
    @CheckInDate date,
    @CheckOutDate date
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @CheckInDate IS NULL OR @CheckOutDate IS NULL OR @CheckOutDate<=@CheckInDate THROW 51001,'Check-out must be later than check-in.',1;
    BEGIN TRY
      BEGIN TRANSACTION;
      DECLARE @Status varchar(12),@Guests tinyint,@Room int,@Count int=0;
      DECLARE @CurrentRooms table(RoomID int PRIMARY KEY);
      INSERT @CurrentRooms(RoomID) SELECT RoomID FROM dbo.ReservationRooms WHERE ReservationID=@ReservationID;
      DECLARE change_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT RoomID FROM @CurrentRooms ORDER BY RoomID;
      OPEN change_cursor; FETCH NEXT FROM change_cursor INTO @Room;
      WHILE @@FETCH_STATUS=0
      BEGIN
        SELECT @Count=@Count+1 FROM dbo.Rooms WITH(UPDLOCK,HOLDLOCK) WHERE RoomID=@Room;
        FETCH NEXT FROM change_cursor INTO @Room;
      END;
      CLOSE change_cursor; DEALLOCATE change_cursor;
      IF @Count=0 THROW 51015,'Reservation must contain at least one room.',1;
      SELECT @Status=Status,@Guests=GuestCount FROM dbo.Reservations WITH(UPDLOCK,HOLDLOCK) WHERE ReservationID=@ReservationID;
      IF @Status IS NULL THROW 51010,'Reservation does not exist.',1;
      IF @Status<>'Confirmed' THROW 51011,'Only confirmed reservations can be changed.',1;
      IF EXISTS(SELECT 1 FROM dbo.ReservationRooms rr JOIN dbo.Rooms r ON r.RoomID=rr.RoomID
        JOIN dbo.Reservations b ON b.ReservationID=rr.ReservationID
        WHERE rr.ReservationID<>@ReservationID AND r.RoomID IN(SELECT RoomID FROM @CurrentRooms)
          AND b.Status IN('Confirmed','CheckedIn') AND b.CheckInDate<@CheckOutDate AND b.CheckOutDate>@CheckInDate)
        THROW 51009,'One or more assigned rooms are unavailable for the new dates.',1;
      UPDATE dbo.Reservations SET CheckInDate=@CheckInDate,CheckOutDate=@CheckOutDate,UpdatedAt=SYSUTCDATETIME() WHERE ReservationID=@ReservationID;
      COMMIT;
    END TRY
    BEGIN CATCH
      IF CURSOR_STATUS('local','change_cursor')>=0 CLOSE change_cursor;
      IF CURSOR_STATUS('local','change_cursor')>-3 DEALLOCATE change_cursor;
      IF XACT_STATE()<>0 ROLLBACK;
      THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CancelReservation
    @ReservationID int,
    @Reason nvarchar(300),
    @CancelledBy nvarchar(120)=N'Guest'
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF NULLIF(LTRIM(RTRIM(@Reason)),N'') IS NULL THROW 51016,'Cancellation reason is required.',1;
    BEGIN TRANSACTION;
    DECLARE @Status varchar(12),@CheckIn date;
    SELECT @Status=Status,@CheckIn=CheckInDate FROM dbo.Reservations WITH(UPDLOCK,HOLDLOCK) WHERE ReservationID=@ReservationID;
    IF @Status IS NULL BEGIN ROLLBACK; THROW 51010,'Reservation does not exist.',1; END;
    IF @Status<>'Confirmed' OR @CheckIn<=CONVERT(date,SYSUTCDATETIME())
    BEGIN ROLLBACK; THROW 51017,'Only confirmed reservations before check-in can be cancelled.',1; END;
    UPDATE dbo.Reservations SET Status='Cancelled',UpdatedAt=SYSUTCDATETIME() WHERE ReservationID=@ReservationID;
    INSERT dbo.Cancellations(ReservationID,Reason,CancelledBy) VALUES(@ReservationID,@Reason,@CancelledBy);
    INSERT dbo.ReservationStatusHistory(ReservationID,OldStatus,NewStatus,ChangedBy,ChangeNote)
    VALUES(@ReservationID,'Confirmed','Cancelled',@CancelledBy,@Reason);
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ProcessRefund
    @ReservationID int,
    @Amount decimal(10,2),
    @CurrencyCode char(3),
    @IdempotencyKey varchar(80),
    @PaymentNote nvarchar(250)=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @Amount IS NULL OR @Amount<=0 THROW 51012,'Refund amount must be positive.',1;
    IF NULLIF(LTRIM(RTRIM(@IdempotencyKey)),'') IS NULL THROW 51005,'Idempotency key is required.',1;
    BEGIN TRY
      BEGIN TRANSACTION;
      IF NOT EXISTS(SELECT 1 FROM dbo.Reservations WITH(UPDLOCK,HOLDLOCK) WHERE ReservationID=@ReservationID)
        THROW 51010,'Reservation does not exist.',1;
      DECLARE @Charges decimal(12,2),@Refunds decimal(12,2),@ChargeCurrency char(3);
      SELECT @Charges=COALESCE(SUM(CASE WHEN PaymentType='Charge' THEN Amount ELSE 0 END),0),
             @Refunds=COALESCE(SUM(CASE WHEN PaymentType='Refund' THEN Amount ELSE 0 END),0),
             @ChargeCurrency=MAX(CASE WHEN PaymentType='Charge' THEN CurrencyCode END)
      FROM dbo.Payments WITH(UPDLOCK,HOLDLOCK) WHERE ReservationID=@ReservationID;
      IF @Charges-@Refunds<@Amount THROW 51018,'Refund exceeds the remaining amount paid.',1;
      IF @ChargeCurrency IS NULL OR @CurrencyCode<>@ChargeCurrency THROW 51019,'Refund currency must match the original charge currency.',1;
      INSERT dbo.Payments(ReservationID,PaymentType,Amount,CurrencyCode,IdempotencyKey,PaymentNote)
      VALUES(@ReservationID,'Refund',@Amount,@CurrencyCode,@IdempotencyKey,@PaymentNote);
      COMMIT;
    END TRY
    BEGIN CATCH
      IF XACT_STATE()<>0 ROLLBACK;
      THROW;
    END CATCH
END;
GO
