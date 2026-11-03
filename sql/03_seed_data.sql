USE TravelBookingDB;
GO
SET NOCOUNT ON;

INSERT dbo.Properties (PropertyCode, PropertyName, AddressLine, City, StateProvince, CountryCode, PostalCode) VALUES
('HBR01',N'Harborlight Hotel',N'18 Lantern Quay',N'Port Azure',N'CA','US',N'94111'),
('PNE02',N'Pinecrest Lodge',N'240 Alpine Way',N'Silverpine',N'CO','US',N'80424'),
('CST03',N'Coastline Suites',N'72 Seabreeze Avenue',N'Mariner Bay',N'FL','US',N'33139');

INSERT dbo.RoomTypes (PropertyID, TypeName, Description, MaxOccupancy, BaseNightlyRate) VALUES
(1,N'Standard',N'Comfortable queen room',2,145.00),(1,N'Family Suite',N'Two beds and sitting area',4,235.00),
(2,N'Mountain Queen',N'Queen room with mountain view',2,175.00),(2,N'Cabin Suite',N'One bedroom lodge suite',4,285.00),
(3,N'Garden King',N'King room near the courtyard',2,160.00),(3,N'Ocean Suite',N'Suite with ocean-facing balcony',4,310.00);

INSERT dbo.Rooms (PropertyID, RoomTypeID, RoomNumber, FloorNumber) VALUES
(1,1,N'101',1),(1,1,N'102',1),(1,1,N'103',1),(1,2,N'201',2),(1,2,N'202',2),
(2,3,N'11',1),(2,3,N'12',1),(2,3,N'13',1),(2,4,N'21',2),(2,4,N'22',2),
(3,5,N'301',3),(3,5,N'302',3),(3,5,N'303',3),(3,6,N'401',4),(3,6,N'402',4);

INSERT dbo.Guests (FirstName, LastName, Email, Phone) VALUES
(N'Avery',N'Quinn',N'avery.quinn@example.test',N'+1-555-0101'),
(N'Jordan',N'Lee',N'jordan.lee@example.test',N'+1-555-0102'),
(N'Morgan',N'Patel',N'morgan.patel@example.test',N'+1-555-0103'),
(N'Riley',N'Santos',N'riley.santos@example.test',N'+1-555-0104'),
(N'Casey',N'Nguyen',N'casey.nguyen@example.test',N'+1-555-0105'),
(N'Taylor',N'Brooks',N'taylor.brooks@example.test',N'+1-555-0106'),
(N'Devon',N'Kim',N'devon.kim@example.test',N'+1-555-0107'),
(N'Skyler',N'Reed',N'skyler.reed@example.test',N'+1-555-0108'),
(N'Rowan',N'Blake',N'rowan.blake@example.test',N'+1-555-0109'),
(N'Emery',N'Flores',N'emery.flores@example.test',N'+1-555-0110');

/* Mix of past and future bookings, including cancelled and completed stays. */
INSERT dbo.Reservations (ConfirmationCode, GuestID, PropertyID, CheckInDate, CheckOutDate, GuestCount, Status, BookedAt) VALUES
('HBR1000001',1,1,'2026-01-12','2026-01-15',2,'CheckedOut','2025-12-20'),
('HBR1000002',2,1,'2026-02-08','2026-02-10',2,'Cancelled','2026-01-05'),
('HBR1000003',3,1,'2026-12-10','2026-12-13',2,'Confirmed','2026-10-01'),
('HBR1000004',4,1,'2027-01-05','2027-01-09',4,'Confirmed','2026-08-15'),
('PNE2000001',5,2,'2026-03-14','2026-03-18',2,'CheckedOut','2026-02-02'),
('PNE2000002',6,2,'2026-12-20','2026-12-23',3,'Confirmed','2026-10-18'),
('PNE2000003',7,2,'2027-02-11','2027-02-14',2,'Confirmed','2026-09-19'),
('CST3000001',8,3,'2026-04-02','2026-04-07',2,'CheckedOut','2026-02-20'),
('CST3000002',9,3,'2026-11-20','2026-11-24',2,'Confirmed','2026-10-27'),
('CST3000003',10,3,'2027-03-03','2027-03-08',4,'Confirmed','2026-10-30'),
('HBR1000005',1,1,'2026-07-09','2026-07-12',2,'CheckedOut','2026-06-01'),
('PNE2000004',2,2,'2026-06-01','2026-06-04',4,'Cancelled','2026-04-22');

INSERT dbo.ReservationRooms (ReservationID, RoomID, NightlyRate) VALUES
(1,1,140.00),(2,2,145.00),(3,3,155.00),(4,4,235.00),(4,5,235.00),
(5,6,170.00),(6,7,180.00),(7,9,285.00),
(8,11,155.00),(9,12,165.00),(10,14,310.00),
(11,1,145.00),(12,10,285.00);

INSERT dbo.Payments (ReservationID, PaymentType, Amount, CurrencyCode, IdempotencyKey, PaymentNote, ProcessedAt) VALUES
(1,'Charge',420.00,'USD','seed-pay-001',N'Final payment','2026-01-02'),
(2,'Charge',290.00,'USD','seed-pay-002',N'Initial charge','2026-01-06'),
(2,'Refund',290.00,'USD','seed-refund-002',N'Cancellation refund','2026-01-07'),
(3,'Charge',200.00,'USD','seed-pay-003',N'Deposit','2026-10-02'),
(4,'Charge',500.00,'USD','seed-pay-004',N'Deposit','2026-08-16'),
(5,'Charge',680.00,'USD','seed-pay-005',N'Paid in full','2026-03-01'),
(6,'Charge',250.00,'USD','seed-pay-006',N'Deposit','2026-10-19'),
(8,'Charge',775.00,'USD','seed-pay-008',N'Paid in full','2026-03-10'),
(9,'Charge',300.00,'USD','seed-pay-009',N'Deposit','2026-10-28'),
(10,'Charge',500.00,'USD','seed-pay-010',N'Deposit','2026-10-31'),
(12,'Charge',570.00,'USD','seed-pay-012',N'Initial charge','2026-04-23'),
(12,'Refund',570.00,'USD','seed-refund-012',N'Cancellation refund','2026-04-24');

INSERT dbo.Cancellations (ReservationID, CancelledAt, Reason, CancelledBy) VALUES
(2,'2026-01-06',N'Guest changed plans',N'Guest'),
(12,'2026-04-23',N'Unexpected schedule change',N'Guest');

INSERT dbo.ReservationStatusHistory (ReservationID, OldStatus, NewStatus, ChangedAt, ChangedBy, ChangeNote) VALUES
(1,NULL,'Confirmed','2025-12-20',N'Seed',N'Initial booking'),(1,'Confirmed','CheckedIn','2026-01-12',N'Seed',N'Guest arrived'),(1,'CheckedIn','CheckedOut','2026-01-15',N'Seed',N'Stay completed'),
(2,NULL,'Confirmed','2026-01-05',N'Seed',N'Initial booking'),(2,'Confirmed','Cancelled','2026-01-06',N'Seed',N'Cancelled before arrival'),
(3,NULL,'Confirmed','2026-10-01',N'Seed',N'Initial booking'),(4,NULL,'Confirmed','2026-08-15',N'Seed',N'Initial booking'),
(5,NULL,'Confirmed','2026-02-02',N'Seed',N'Initial booking'),(5,'Confirmed','CheckedIn','2026-03-14',N'Seed',N'Guest arrived'),(5,'CheckedIn','CheckedOut','2026-03-18',N'Seed',N'Stay completed'),
(6,NULL,'Confirmed','2026-10-18',N'Seed',N'Initial booking'),(7,NULL,'Confirmed','2026-09-19',N'Seed',N'Initial booking'),
(8,NULL,'Confirmed','2026-02-20',N'Seed',N'Initial booking'),(8,'Confirmed','CheckedIn','2026-04-02',N'Seed',N'Guest arrived'),(8,'CheckedIn','CheckedOut','2026-04-07',N'Seed',N'Stay completed'),
(9,NULL,'Confirmed','2026-10-27',N'Seed',N'Initial booking'),(10,NULL,'Confirmed','2026-10-30',N'Seed',N'Initial booking'),
(11,NULL,'Confirmed','2026-06-01',N'Seed',N'Initial booking'),(11,'Confirmed','CheckedIn','2026-07-09',N'Seed',N'Guest arrived'),(11,'CheckedIn','CheckedOut','2026-07-12',N'Seed',N'Stay completed'),
(12,NULL,'Confirmed','2026-04-22',N'Seed',N'Initial booking'),(12,'Confirmed','Cancelled','2026-04-23',N'Seed',N'Cancelled before arrival');
GO
