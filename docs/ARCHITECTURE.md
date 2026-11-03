# System architecture

This project provides a SQL Server data layer. A user or future booking application invokes stored procedures for writes and queries views/reports for reads. It does not include an application server, website, or user interface.

## Components

```mermaid
flowchart TB
    subgraph Consumers
      B[Booking application or analyst]
      S[SQL client: SSMS, Azure Data Studio, or sqlcmd]
    end
    B -->|Stored procedure calls| SP
    S -->|T-SQL scripts and queries| SP
    S -->|Report queries| RV
    subgraph SQLServer[Microsoft SQL Server]
      SP[Stored procedures]
      RV[Views and report queries]
      SP -->|Validate and write in transactions| DB[(Relational tables)]
      RV -->|Join and aggregate| DB
      DB --- C[PK, FK, UNIQUE, CHECK constraints]
      DB --- IX[Search and reporting indexes]
      DB --- AU[Reservation status and payment audit data]
    end
```

## Reservation creation flow

```mermaid
sequenceDiagram
    actor Client
    participant Proc as usp_CreateReservation
    participant SQL as SQL Server
    participant Inv as Room inventory and reservations
    Client->>Proc: Property, dates, guests, room IDs
    Proc->>SQL: Begin transaction with HOLDLOCK inventory locks
    Proc->>Inv: Lock selected room rows in ID order
    Proc->>Inv: Validate property, capacity, active status, and overlap
    alt A room is invalid or occupied
        Proc->>SQL: Roll back
        Proc-->>Client: Return validation error
    else All rooms are available
        Proc->>Inv: Insert reservation and room assignments
        Proc->>SQL: Insert initial status history
        Proc->>SQL: Commit
        Proc-->>Client: Return reservation ID and confirmation code
    end
```

The same inventory locking and overlap rule is used when rooms are added or reservation dates are changed. The half-open interval rule treats checkout as unoccupied, allowing same-day turnover. Payment and refund procedures lock the reservation and validate ledger totals before inserting their audit entry.

## Data flow

1. A client searches using `usp_SearchAvailability` for a property, date range, and party size.
2. The client submits selected `RoomID` values to `usp_CreateReservation`.
3. The procedure locks inventory, checks availability, writes the reservation and its room assignments, and appends the initial status event.
4. Payment, cancellation, and refund procedures append financial or cancellation audit records and update reservation status where applicable.
5. Views and report queries aggregate reservation, inventory, and payment events for operations and analysis.
