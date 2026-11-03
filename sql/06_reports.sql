USE TravelBookingDB;
GO

/* 1. Occupancy by property/month. Assigned room-nights divided by available room-nights. */
DECLARE @ReportStart date='2026-01-01', @ReportEnd date='2027-12-31';
;WITH MonthStarts AS (
    SELECT DATEFROMPARTS(YEAR(@ReportStart),MONTH(@ReportStart),1) AS MonthStart
    UNION ALL SELECT DATEADD(month,1,MonthStart) FROM MonthStarts
    WHERE DATEADD(month,1,MonthStart)<DATEFROMPARTS(YEAR(@ReportEnd),MONTH(@ReportEnd),1)
), PropertyMonths AS (
    SELECT p.PropertyID,p.PropertyName,m.MonthStart,
           DATEDIFF(day,m.MonthStart,DATEADD(month,1,m.MonthStart)) AS DaysInMonth,
           (SELECT COUNT(*) FROM dbo.Rooms rm WHERE rm.PropertyID=p.PropertyID AND rm.IsActive=1) AS ActiveRoomCount
    FROM dbo.Properties p CROSS JOIN MonthStarts m
), Occupied AS (
    SELECT r.PropertyID,pm.MonthStart,
           SUM(DATEDIFF(day,CASE WHEN r.CheckInDate>pm.MonthStart THEN r.CheckInDate ELSE pm.MonthStart END,
                            CASE WHEN r.CheckOutDate<DATEADD(month,1,pm.MonthStart) THEN r.CheckOutDate ELSE DATEADD(month,1,pm.MonthStart) END)) AS OccupiedRoomNights
    FROM dbo.Reservations r
    JOIN dbo.ReservationRooms rr ON rr.ReservationID=r.ReservationID
    JOIN PropertyMonths pm ON pm.PropertyID=r.PropertyID
    WHERE r.Status IN('Confirmed','CheckedIn','CheckedOut')
      AND r.CheckInDate<DATEADD(month,1,pm.MonthStart) AND r.CheckOutDate>pm.MonthStart
    GROUP BY r.PropertyID,pm.MonthStart
)
SELECT pm.PropertyName,pm.MonthStart,COALESCE(o.OccupiedRoomNights,0) AS OccupiedRoomNights,
       pm.ActiveRoomCount*pm.DaysInMonth AS AvailableRoomNights,
       CAST(100.0*COALESCE(o.OccupiedRoomNights,0)/NULLIF(pm.ActiveRoomCount*pm.DaysInMonth,0) AS decimal(6,2)) AS OccupancyRatePct
FROM PropertyMonths pm LEFT JOIN Occupied o ON o.PropertyID=pm.PropertyID AND o.MonthStart=pm.MonthStart
ORDER BY pm.PropertyName,pm.MonthStart OPTION(MAXRECURSION 100);

/* 2. Net revenue by property and month; refunds reduce revenue. */
SELECT PropertyName,RevenueMonth,GrossCharges,Refunds,NetRevenue
FROM dbo.vw_MonthlyPropertyRevenue ORDER BY RevenueMonth,PropertyName;

/* 3. Cancellations by property and month. */
SELECT PropertyName,DATEFROMPARTS(YEAR(CancelledAt),MONTH(CancelledAt),1) AS CancellationMonth,
       COUNT(*) AS CancellationCount,AVG(CONVERT(decimal(8,2),BookingLeadDays)) AS AvgLeadDaysAtCancellation
FROM dbo.vw_CancellationSummary
GROUP BY PropertyName,DATEFROMPARTS(YEAR(CancelledAt),MONTH(CancelledAt),1)
ORDER BY CancellationMonth,PropertyName;

/* 4. Booking lead time by property, with ranking and preceding row comparison. */
;WITH LeadTimes AS (
    SELECT p.PropertyName,r.ReservationID,r.BookedAt,r.CheckInDate,
           DATEDIFF(day,CONVERT(date,r.BookedAt),r.CheckInDate) AS LeadDays
    FROM dbo.Reservations r JOIN dbo.Properties p ON p.PropertyID=r.PropertyID
    WHERE r.Status<>'Cancelled'
)
SELECT PropertyName,ReservationID,BookedAt,CheckInDate,LeadDays,
       ROW_NUMBER() OVER(PARTITION BY PropertyName ORDER BY LeadDays DESC) AS LeadTimeRank,
       LAG(LeadDays) OVER(PARTITION BY PropertyName ORDER BY CheckInDate,ReservationID) AS PreviousBookingLeadDays
FROM LeadTimes ORDER BY PropertyName,LeadTimeRank;

/* 5. Room-type demand, including stays and booked room-nights. */
SELECT p.PropertyName,rt.TypeName,
       COUNT(DISTINCT rr.ReservationID) AS Reservations,
       COUNT(*) AS RoomAssignments,
       SUM(DATEDIFF(day,r.CheckInDate,r.CheckOutDate)) AS BookedRoomNights,
       SUM(rr.NightlyRate*DATEDIFF(day,r.CheckInDate,r.CheckOutDate)) AS BookedRoomValue
FROM dbo.ReservationRooms rr
JOIN dbo.Reservations r ON r.ReservationID=rr.ReservationID
JOIN dbo.Rooms rm ON rm.RoomID=rr.RoomID
JOIN dbo.RoomTypes rt ON rt.RoomTypeID=rm.RoomTypeID AND rt.PropertyID=rm.PropertyID
JOIN dbo.Properties p ON p.PropertyID=r.PropertyID
WHERE r.Status<>'Cancelled'
GROUP BY p.PropertyName,rt.TypeName ORDER BY BookedRoomNights DESC;

/* 6. Upcoming arrivals and departures. */
SELECT EventDate,EventType,PropertyName,ConfirmationCode,FirstName,LastName,CheckInDate,CheckOutDate
FROM dbo.vw_UpcomingStayEvents ORDER BY EventDate,PropertyName,ConfirmationCode;

/* 7. Reservation value ranking using a correlated subquery and window function. */
SELECT p.PropertyName,r.ReservationID,r.ConfirmationCode,
       (SELECT SUM(rr.NightlyRate*DATEDIFF(day,r.CheckInDate,r.CheckOutDate))
        FROM dbo.ReservationRooms rr WHERE rr.ReservationID=r.ReservationID) AS StayValue,
       DENSE_RANK() OVER(PARTITION BY p.PropertyID ORDER BY
         (SELECT SUM(rr2.NightlyRate*DATEDIFF(day,r.CheckInDate,r.CheckOutDate))
          FROM dbo.ReservationRooms rr2 WHERE rr2.ReservationID=r.ReservationID) DESC) AS PropertyValueRank
FROM dbo.Reservations r JOIN dbo.Properties p ON p.PropertyID=r.PropertyID
WHERE r.Status<>'Cancelled' ORDER BY p.PropertyName,PropertyValueRank;
GO
