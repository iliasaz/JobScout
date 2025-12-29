# Persistence Implementation Plan

## Overview

Add SQLite persistence for job postings using:
- **StructuredQueries** - Type-safe SQL query builder with `@Table` macro
- **GRDB** - SQLite database library for Swift

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      ContentView                            │
│                          │                                  │
│                          ▼                                  │
│                   JobRepository                             │
│                    │         │                              │
│         ┌──────────┘         └──────────┐                   │
│         ▼                               ▼                   │
│  StructuredQueries              GRDB DatabaseQueue          │
│  (Query Building)               (Query Execution)           │
│         │                               │                   │
│         └──────────┐         ┌──────────┘                   │
│                    ▼         ▼                              │
│                    SQLite Database                          │
│              (~/Library/Application Support)                │
└─────────────────────────────────────────────────────────────┘
```

## Database Schema

### Tables

#### 1. `job_sources` - Track fetched URLs
```sql
CREATE TABLE "job_sources" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "url" TEXT NOT NULL UNIQUE,
  "name" TEXT NOT NULL,
  "last_fetched_at" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### 2. `job_postings` - Main job data
```sql
CREATE TABLE "job_postings" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "source_id" INTEGER NOT NULL REFERENCES "job_sources"("id") ON DELETE CASCADE,
  "company" TEXT NOT NULL,
  "role" TEXT NOT NULL,
  "location" TEXT NOT NULL,
  "country" TEXT NOT NULL DEFAULT 'USA',
  "category" TEXT NOT NULL DEFAULT 'Other',
  "company_link" TEXT,
  "simplify_link" TEXT,
  "date_posted" TEXT,
  "notes" TEXT,
  "is_faang" INTEGER NOT NULL DEFAULT 0,
  "created_at" TEXT NOT NULL DEFAULT (datetime('now')),
  "updated_at" TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE("source_id", "company", "role", "location", "company_link")
);

CREATE INDEX "idx_job_postings_source" ON "job_postings"("source_id");
CREATE INDEX "idx_job_postings_country" ON "job_postings"("country");
CREATE INDEX "idx_job_postings_category" ON "job_postings"("category");
CREATE INDEX "idx_job_postings_company" ON "job_postings"("company");
```

#### 3. `user_job_status` - Track user interactions
```sql
CREATE TABLE "user_job_status" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "job_id" INTEGER NOT NULL UNIQUE REFERENCES "job_postings"("id") ON DELETE CASCADE,
  "status" TEXT NOT NULL DEFAULT 'new', -- new, interested, applied, rejected, archived
  "notes" TEXT,
  "applied_at" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (datetime('now')),
  "updated_at" TEXT NOT NULL DEFAULT (datetime('now'))
);
```

## Swift Models with @Table Macro

### JobSource.swift
```swift
import StructuredQueries

@Table("job_sources")
struct JobSource {
    let id: Int
    var url: String
    var name: String
    @Column("last_fetched_at")
    var lastFetchedAt: Date?
    @Column("created_at")
    let createdAt: Date
}
```

### PersistedJobPosting.swift
```swift
import StructuredQueries

@Table("job_postings")
struct PersistedJobPosting {
    let id: Int
    @Column("source_id")
    var sourceId: Int
    var company: String
    var role: String
    var location: String
    var country: String
    var category: String
    @Column("company_link")
    var companyLink: String?
    @Column("simplify_link")
    var simplifyLink: String?
    @Column("date_posted")
    var datePosted: String?
    var notes: String?
    @Column("is_faang")
    var isFAANG: Bool
    @Column("created_at")
    let createdAt: Date
    @Column("updated_at")
    var updatedAt: Date
}
```

### UserJobStatus.swift
```swift
import StructuredQueries

enum JobStatus: String, QueryBindable {
    case new, interested, applied, rejected, archived
}

@Table("user_job_status")
struct UserJobStatus {
    let id: Int
    @Column("job_id")
    var jobId: Int
    var status: JobStatus
    var notes: String?
    @Column("applied_at")
    var appliedAt: Date?
    @Column("created_at")
    let createdAt: Date
    @Column("updated_at")
    var updatedAt: Date
}
```

## Implementation Steps

### Phase 1: Database Setup

1. **Add GRDB Package Dependency**
   - Add GRDB.swift to Package dependencies in Xcode

2. **Create DatabaseManager.swift**
   - Initialize database at app launch
   - Handle migrations
   - Provide DatabaseQueue access
   ```swift
   actor DatabaseManager {
       static let shared = DatabaseManager()
       private var dbQueue: DatabaseQueue?

       func setupDatabase() async throws -> DatabaseQueue
       func migrate(_ db: Database) throws
   }
   ```

3. **Create Migration Files**
   - `Migration_001_CreateTables.swift` - Initial schema

### Phase 2: Repository Layer

4. **Create JobRepository.swift**
   ```swift
   actor JobRepository {
       private let db: DatabaseQueue

       // Sources
       func createSource(url: String, name: String) async throws -> JobSource
       func getSource(url: String) async throws -> JobSource?
       func updateLastFetched(sourceId: Int) async throws

       // Jobs
       func saveJobs(_ jobs: [JobPosting], sourceId: Int) async throws
       func getJobs(sourceId: Int?) async throws -> [PersistedJobPosting]
       func searchJobs(query: String) async throws -> [PersistedJobPosting]
       func getJobsByCountry(_ country: String) async throws -> [PersistedJobPosting]
       func getJobsByCategory(_ category: String) async throws -> [PersistedJobPosting]

       // User Status
       func setJobStatus(_ jobId: Int, status: JobStatus) async throws
       func getJobStatus(_ jobId: Int) async throws -> UserJobStatus?
   }
   ```

### Phase 3: Query Examples with StructuredQueries

5. **Example Queries**
   ```swift
   // Get all jobs from a source
   PersistedJobPosting
       .where { $0.sourceId == sourceId }
       .order { $0.createdAt.desc() }

   // Search jobs
   PersistedJobPosting
       .where {
           $0.company.collate(.nocase).like("%\(query)%")
           || $0.role.collate(.nocase).like("%\(query)%")
       }

   // Filter by country and category
   PersistedJobPosting
       .where { $0.country == "USA" && $0.category == "Software Engineering" }

   // Get jobs with user status (LEFT JOIN)
   PersistedJobPosting
       .leftJoin(UserJobStatus.all) { $0.id == $1.jobId }
       .select { ($0, $1.status) }

   // Insert new jobs
   PersistedJobPosting.insert {
       PersistedJobPosting.Draft(
           sourceId: sourceId,
           company: job.company,
           role: job.role,
           // ...
       )
   }

   // Update job status
   UserJobStatus
       .where { $0.jobId == jobId }
       .update { $0.status = .applied }
   ```

### Phase 4: UI Integration

6. **Update ContentView**
   - Add persistence toggle/indicator
   - Show saved job count
   - Add "Save" button after fetch
   - Add job status column/controls

7. **Create JobListView (optional refactor)**
   - Separate view for job list with persistence features
   - Add swipe actions for status changes
   - Add context menus

### Phase 5: Additional Features

8. **Add Observation**
   - Use GRDB's ValueObservation for reactive updates
   - Auto-refresh UI when database changes

9. **Add Export/Import**
   - Export jobs to CSV/JSON
   - Import from backup

## File Structure

```
JobScout/
├── Database/
│   ├── DatabaseManager.swift
│   ├── Migrations/
│   │   └── Migration_001_CreateTables.swift
│   └── GRDB+StructuredQueries.swift (integration helpers)
├── Models/
│   ├── JobPosting.swift (existing - in-memory)
│   ├── PersistedJobPosting.swift (new - @Table)
│   ├── JobSource.swift (new - @Table)
│   └── UserJobStatus.swift (new - @Table)
├── Repositories/
│   └── JobRepository.swift
└── ...
```

## Dependencies

1. **swift-structured-queries** (already added)
   - `StructuredQueries` module

2. **GRDB.swift** (to add)
   - `GRDB` module
   - https://github.com/groue/GRDB.swift

3. **Optional: sqlite-data** (Point-Free's GRDB integration)
   - Provides `StructuredQueriesGRDB` module
   - Simplifies GRDB + StructuredQueries integration
   - https://github.com/pointfreeco/sqlite-data

## Notes

- StructuredQueries only builds queries; GRDB executes them
- Use `#sql` macro for migrations (schema changes should be SQL strings)
- The `@Table` macro generates type-safe query APIs automatically
- Consider using Point-Free's `sqlite-data` package which bundles GRDB integration
