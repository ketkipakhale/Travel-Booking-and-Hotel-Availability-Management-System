USE TravelBookingDB;
GO
CREATE INDEX IX_Rooms_Property_Active_Type ON dbo.Rooms(PropertyID, IsActive, RoomTypeID) INCLUDE (RoomNumber);
CREATE INDEX IX_Reservations_Property_Dates_Status ON dbo.Reservations(PropertyID, CheckInDate, CheckOutDate, Status) INCLUDE (GuestCount, GuestID, BookedAt);
CREATE INDEX IX_ReservationRooms_Room_Reservation ON dbo.ReservationRooms(RoomID, ReservationID) INCLUDE (NightlyRate);
CREATE INDEX IX_Payments_Reservation_Type_Date ON dbo.Payments(ReservationID, PaymentType, ProcessedAt) INCLUDE (Amount, CurrencyCode);
CREATE INDEX IX_Reservations_Status_CheckIn ON dbo.Reservations(Status, CheckInDate) INCLUDE (CheckOutDate, PropertyID, GuestID);
CREATE INDEX IX_StatusHistory_Reservation_ChangedAt ON dbo.ReservationStatusHistory(ReservationID, ChangedAt DESC);
GO
