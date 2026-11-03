USE TravelBookingDB;
GO

CREATE TABLE dbo.Properties (
    PropertyID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Properties PRIMARY KEY,
    PropertyCode varchar(12) NOT NULL CONSTRAINT UQ_Properties_PropertyCode UNIQUE,
    PropertyName nvarchar(120) NOT NULL,
    AddressLine nvarchar(200) NOT NULL,
    City nvarchar(80) NOT NULL,
    StateProvince nvarchar(80) NULL,
    CountryCode char(2) NOT NULL,
    PostalCode nvarchar(20) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_Properties_IsActive DEFAULT (1),
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_Properties_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt datetime2(0) NOT NULL CONSTRAINT DF_Properties_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_Properties_CountryCode CHECK (CountryCode LIKE '[A-Z][A-Z]')
);

CREATE TABLE dbo.RoomTypes (
    RoomTypeID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_RoomTypes PRIMARY KEY,
    PropertyID int NOT NULL,
    TypeName nvarchar(60) NOT NULL,
    Description nvarchar(300) NULL,
    MaxOccupancy tinyint NOT NULL,
    BaseNightlyRate decimal(10,2) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_RoomTypes_IsActive DEFAULT (1),
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_RoomTypes_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt datetime2(0) NOT NULL CONSTRAINT DF_RoomTypes_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_RoomTypes_Properties FOREIGN KEY (PropertyID) REFERENCES dbo.Properties(PropertyID),
    CONSTRAINT UQ_RoomTypes_Property_Type UNIQUE (PropertyID, TypeName),
    CONSTRAINT UQ_RoomTypes_Property_RoomType UNIQUE (PropertyID, RoomTypeID),
    CONSTRAINT CK_RoomTypes_MaxOccupancy CHECK (MaxOccupancy BETWEEN 1 AND 12),
    CONSTRAINT CK_RoomTypes_BaseNightlyRate CHECK (BaseNightlyRate >= 0)
);

CREATE TABLE dbo.Rooms (
    RoomID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Rooms PRIMARY KEY,
    PropertyID int NOT NULL,
    RoomTypeID int NOT NULL,
    RoomNumber nvarchar(12) NOT NULL,
    FloorNumber smallint NULL,
    IsActive bit NOT NULL CONSTRAINT DF_Rooms_IsActive DEFAULT (1),
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_Rooms_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt datetime2(0) NOT NULL CONSTRAINT DF_Rooms_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Rooms_Properties FOREIGN KEY (PropertyID) REFERENCES dbo.Properties(PropertyID),
    CONSTRAINT FK_Rooms_RoomTypes FOREIGN KEY (PropertyID, RoomTypeID) REFERENCES dbo.RoomTypes(PropertyID, RoomTypeID),
    CONSTRAINT UQ_Rooms_Property_RoomNumber UNIQUE (PropertyID, RoomNumber)
);

CREATE TABLE dbo.Guests (
    GuestID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Guests PRIMARY KEY,
    FirstName nvarchar(60) NOT NULL,
    LastName nvarchar(60) NOT NULL,
    Email nvarchar(254) NOT NULL CONSTRAINT UQ_Guests_Email UNIQUE,
    Phone nvarchar(30) NULL,
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_Guests_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt datetime2(0) NOT NULL CONSTRAINT DF_Guests_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_Guests_Email CHECK (Email LIKE N'%_@_%._%')
);

CREATE TABLE dbo.Reservations (
    ReservationID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Reservations PRIMARY KEY,
    ConfirmationCode char(10) NOT NULL CONSTRAINT UQ_Reservations_ConfirmationCode UNIQUE,
    GuestID int NOT NULL,
    PropertyID int NOT NULL,
    CheckInDate date NOT NULL,
    CheckOutDate date NOT NULL,
    GuestCount tinyint NOT NULL,
    Status varchar(12) NOT NULL CONSTRAINT DF_Reservations_Status DEFAULT ('Confirmed'),
    BookedAt datetime2(0) NOT NULL CONSTRAINT DF_Reservations_BookedAt DEFAULT (SYSUTCDATETIME()),
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_Reservations_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt datetime2(0) NOT NULL CONSTRAINT DF_Reservations_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Reservations_Guests FOREIGN KEY (GuestID) REFERENCES dbo.Guests(GuestID),
    CONSTRAINT FK_Reservations_Properties FOREIGN KEY (PropertyID) REFERENCES dbo.Properties(PropertyID),
    CONSTRAINT CK_Reservations_DateRange CHECK (CheckOutDate > CheckInDate),
    CONSTRAINT CK_Reservations_GuestCount CHECK (GuestCount BETWEEN 1 AND 20),
    CONSTRAINT CK_Reservations_Status CHECK (Status IN ('Confirmed','CheckedIn','CheckedOut','Cancelled'))
);

CREATE TABLE dbo.ReservationRooms (
    ReservationID int NOT NULL,
    RoomID int NOT NULL,
    NightlyRate decimal(10,2) NOT NULL,
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_ReservationRooms_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_ReservationRooms PRIMARY KEY (ReservationID, RoomID),
    CONSTRAINT FK_ReservationRooms_Reservations FOREIGN KEY (ReservationID) REFERENCES dbo.Reservations(ReservationID),
    CONSTRAINT FK_ReservationRooms_Rooms FOREIGN KEY (RoomID) REFERENCES dbo.Rooms(RoomID),
    CONSTRAINT CK_ReservationRooms_NightlyRate CHECK (NightlyRate >= 0)
);

CREATE TABLE dbo.Payments (
    PaymentID bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_Payments PRIMARY KEY,
    ReservationID int NOT NULL,
    PaymentType varchar(8) NOT NULL,
    Amount decimal(10,2) NOT NULL,
    CurrencyCode char(3) NOT NULL,
    IdempotencyKey varchar(80) NOT NULL CONSTRAINT UQ_Payments_IdempotencyKey UNIQUE,
    PaymentNote nvarchar(250) NULL,
    ProcessedAt datetime2(0) NOT NULL CONSTRAINT DF_Payments_ProcessedAt DEFAULT (SYSUTCDATETIME()),
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_Payments_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Payments_Reservations FOREIGN KEY (ReservationID) REFERENCES dbo.Reservations(ReservationID),
    CONSTRAINT CK_Payments_Type CHECK (PaymentType IN ('Charge','Refund')),
    CONSTRAINT CK_Payments_Amount CHECK (Amount > 0),
    CONSTRAINT CK_Payments_Currency CHECK (CurrencyCode LIKE '[A-Z][A-Z][A-Z]')
);

CREATE TABLE dbo.Cancellations (
    CancellationID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Cancellations PRIMARY KEY,
    ReservationID int NOT NULL CONSTRAINT UQ_Cancellations_Reservation UNIQUE,
    CancelledAt datetime2(0) NOT NULL CONSTRAINT DF_Cancellations_CancelledAt DEFAULT (SYSUTCDATETIME()),
    Reason nvarchar(300) NOT NULL,
    CancelledBy nvarchar(120) NOT NULL,
    CONSTRAINT FK_Cancellations_Reservations FOREIGN KEY (ReservationID) REFERENCES dbo.Reservations(ReservationID)
);

CREATE TABLE dbo.ReservationStatusHistory (
    StatusHistoryID bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_ReservationStatusHistory PRIMARY KEY,
    ReservationID int NOT NULL,
    OldStatus varchar(12) NULL,
    NewStatus varchar(12) NOT NULL,
    ChangedAt datetime2(0) NOT NULL CONSTRAINT DF_ReservationStatusHistory_ChangedAt DEFAULT (SYSUTCDATETIME()),
    ChangedBy nvarchar(120) NOT NULL CONSTRAINT DF_ReservationStatusHistory_ChangedBy DEFAULT (SUSER_SNAME()),
    ChangeNote nvarchar(300) NULL,
    CONSTRAINT FK_ReservationStatusHistory_Reservations FOREIGN KEY (ReservationID) REFERENCES dbo.Reservations(ReservationID),
    CONSTRAINT CK_ReservationStatusHistory_OldStatus CHECK (OldStatus IS NULL OR OldStatus IN ('Confirmed','CheckedIn','CheckedOut','Cancelled')),
    CONSTRAINT CK_ReservationStatusHistory_NewStatus CHECK (NewStatus IN ('Confirmed','CheckedIn','CheckedOut','Cancelled'))
);
GO
