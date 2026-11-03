/* Run with a login permitted to create databases. */
IF DB_ID(N'TravelBookingDB') IS NULL
    EXEC(N'CREATE DATABASE TravelBookingDB');
GO
USE TravelBookingDB;
GO
