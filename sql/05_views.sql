USE TravelBookingDB;
GO

CREATE OR ALTER VIEW dbo.vw_ReservationFinancials
AS
SELECT r.ReservationID, r.ConfirmationCode, r.PropertyID, r.GuestID, r.Status,
       SUM(CASE WHEN p.PaymentType='Charge' THEN p.Amount ELSE 0 END) AS TotalCharged,
       SUM(CASE WHEN p.PaymentType='Refund' THEN p.Amount ELSE 0 END) AS TotalRefunded,
       SUM(CASE WHEN p.PaymentType='Charge' THEN p.Amount WHEN p.PaymentType='Refund' THEN -p.Amount ELSE 0 END) AS NetPaid
FROM dbo.Reservations r
LEFT JOIN dbo.Payments p ON p.ReservationID=r.ReservationID
GROUP BY r.ReservationID,r.ConfirmationCode,r.PropertyID,r.GuestID,r.Status;
GO

CREATE OR ALTER VIEW dbo.vw_MonthlyPropertyRevenue
AS
SELECT r.PropertyID,p.PropertyName,
       DATEFROMPARTS(YEAR(pay.ProcessedAt),MONTH(pay.ProcessedAt),1) AS RevenueMonth,
       SUM(CASE WHEN pay.PaymentType='Charge' THEN pay.Amount ELSE -pay.Amount END) AS NetRevenue,
       SUM(CASE WHEN pay.PaymentType='Charge' THEN pay.Amount ELSE 0 END) AS GrossCharges,
       SUM(CASE WHEN pay.PaymentType='Refund' THEN pay.Amount ELSE 0 END) AS Refunds
FROM dbo.Payments pay
JOIN dbo.Reservations r ON r.ReservationID=pay.ReservationID
JOIN dbo.Properties p ON p.PropertyID=r.PropertyID
GROUP BY r.PropertyID,p.PropertyName,DATEFROMPARTS(YEAR(pay.ProcessedAt),MONTH(pay.ProcessedAt),1);
GO

CREATE OR ALTER VIEW dbo.vw_CancellationSummary
AS
SELECT c.CancellationID,c.ReservationID,r.ConfirmationCode,r.PropertyID,p.PropertyName,
       r.GuestID,g.FirstName,g.LastName,r.CheckInDate,r.CheckOutDate,c.CancelledAt,c.Reason,c.CancelledBy,
       DATEDIFF(day,CONVERT(date,r.BookedAt),r.CheckInDate) AS BookingLeadDays
FROM dbo.Cancellations c
JOIN dbo.Reservations r ON r.ReservationID=c.ReservationID
JOIN dbo.Properties p ON p.PropertyID=r.PropertyID
JOIN dbo.Guests g ON g.GuestID=r.GuestID;
GO

CREATE OR ALTER VIEW dbo.vw_UpcomingStayEvents
AS
SELECT r.ReservationID,r.ConfirmationCode,r.PropertyID,p.PropertyName,r.GuestID,
       g.FirstName,g.LastName,r.CheckInDate,r.CheckOutDate,r.Status,
       CASE WHEN r.CheckInDate>=CONVERT(date,SYSUTCDATETIME()) THEN 'CheckIn' ELSE 'CheckOut' END AS EventType,
       CASE WHEN r.CheckInDate>=CONVERT(date,SYSUTCDATETIME()) THEN r.CheckInDate ELSE r.CheckOutDate END AS EventDate
FROM dbo.Reservations r
JOIN dbo.Properties p ON p.PropertyID=r.PropertyID
JOIN dbo.Guests g ON g.GuestID=r.GuestID
WHERE r.Status IN('Confirmed','CheckedIn')
  AND (r.CheckInDate>=CONVERT(date,SYSUTCDATETIME()) OR r.CheckOutDate>=CONVERT(date,SYSUTCDATETIME()));
GO
