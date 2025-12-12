# Bezgelor Account Portal - Implementation Plan

**Date:** 2025-12-12
**Design Doc:** [2025-12-12-account-portal-design.md](./2025-12-12-account-portal-design.md)
**Status:** Ready for Implementation

---

## Phase 1: Foundation

### Batch 1.1: Phoenix App Scaffold
Create the new `bezgelor_portal` umbrella app with Phoenix and LiveView.

- [ ] **1.1.1** Generate Phoenix app in umbrella
  ```bash
  cd apps && mix phx.new bezgelor_portal --no-ecto --no-mailer --no-dashboard
  ```
  - Use `--no-ecto` since we use `bezgelor_db`
  - Use `--no-mailer` (add later for email verification)
  - Use `--no-dashboard` (we're building custom analytics)

- [ ] **1.1.2** Update `bezgelor_portal/mix.exs` dependencies
  - Add umbrella deps: `bezgelor_db`, `bezgelor_crypto`, `bezgelor_world`, `bezgelor_data`
  - Add `phoenix_live_view`, `tailwind`, `heroicons`
  - Add `nimble_totp` for TOTP support

- [ ] **1.1.3** Configure Tailwind CSS
  - Add tailwind config for portal styling
  - Set up asset pipeline in `config/config.exs`

- [ ] **1.1.4** Create base layouts
  - `root.html.heex` - HTML shell with Tailwind
  - `app.html.heex` - Main app layout (for logged-in users)
  - `auth.html.heex` - Auth pages layout (login/register)

- [ ] **1.1.5** Verify app compiles and runs
  - `mix deps.get && mix compile`
  - Start on port 4001 (separate from API on 4000)

### Batch 1.2: RBAC Database Schema
Add permissions, roles, and account extensions to `bezgelor_db`.

- [ ] **1.2.1** Create migration: `create_permissions`
  ```elixir
  create table(:permissions) do
    add :key, :string, null: false
    add :category, :string, null: false
    add :description, :text
    timestamps()
  end
  create unique_index(:permissions, [:key])
  ```

- [ ] **1.2.2** Create migration: `create_roles`
  ```elixir
  create table(:roles) do
    add :name, :string, null: false
    add :description, :text
    add :protected, :boolean, default: false
    timestamps()
  end
  create unique_index(:roles, [:name])
  ```

- [ ] **1.2.3** Create migration: `create_role_permissions`
  ```elixir
  create table(:role_permissions, primary_key: false) do
    add :role_id, references(:roles, on_delete: :delete_all), null: false
    add :permission_id, references(:permissions, on_delete: :delete_all), null: false
  end
  create unique_index(:role_permissions, [:role_id, :permission_id])
  ```

- [ ] **1.2.4** Create migration: `create_account_roles`
  ```elixir
  create table(:account_roles, primary_key: false) do
    add :account_id, references(:accounts, on_delete: :delete_all), null: false
    add :role_id, references(:roles, on_delete: :delete_all), null: false
    add :assigned_by, references(:accounts, on_delete: :nilify_all)
    add :assigned_at, :utc_datetime, null: false
  end
  create unique_index(:account_roles, [:account_id, :role_id])
  ```

- [ ] **1.2.5** Create migration: `extend_accounts_for_portal`
  ```elixir
  alter table(:accounts) do
    add :email_verified_at, :utc_datetime
    add :totp_secret_encrypted, :binary
    add :totp_enabled_at, :utc_datetime
    add :backup_codes_hashed, {:array, :string}
    add :discord_id, :string
    add :discord_username, :string
    add :discord_linked_at, :utc_datetime
  end
  create index(:accounts, [:discord_id])
  ```

- [ ] **1.2.6** Create migration: `create_admin_audit_log`
  ```elixir
  create table(:admin_audit_log) do
    add :admin_account_id, references(:accounts, on_delete: :nilify_all)
    add :action, :string, null: false
    add :target_type, :string
    add :target_id, :integer
    add :details, :map
    add :ip_address, :inet
    timestamps(updated_at: false)
  end
  create index(:admin_audit_log, [:admin_account_id])
  create index(:admin_audit_log, [:action])
  create index(:admin_audit_log, [:inserted_at])
  ```

- [ ] **1.2.7** Run migrations and verify
  ```bash
  mix ecto.migrate
  ```

### Batch 1.3: RBAC Ecto Schemas
Create Ecto schemas for the new tables.

- [ ] **1.3.1** Create `BezgelorDb.Schema.Permission`
  - Fields: `key`, `category`, `description`
  - No changeset needed (seeded, not user-editable)

- [ ] **1.3.2** Create `BezgelorDb.Schema.Role`
  - Fields: `name`, `description`, `protected`
  - Associations: `has_many :role_permissions`, `many_to_many :permissions`
  - Changeset for create/update (validate name uniqueness)

- [ ] **1.3.3** Create `BezgelorDb.Schema.RolePermission`
  - Fields: `role_id`, `permission_id`
  - Associations: `belongs_to :role`, `belongs_to :permission`

- [ ] **1.3.4** Create `BezgelorDb.Schema.AccountRole`
  - Fields: `account_id`, `role_id`, `assigned_by`, `assigned_at`
  - Associations: `belongs_to :account`, `belongs_to :role`, `belongs_to :assigner`

- [ ] **1.3.5** Create `BezgelorDb.Schema.AdminAuditLog`
  - Fields: `admin_account_id`, `action`, `target_type`, `target_id`, `details`, `ip_address`
  - Associations: `belongs_to :admin_account`

- [ ] **1.3.6** Update `BezgelorDb.Schema.Account`
  - Add new fields: `email_verified_at`, `totp_secret_encrypted`, `totp_enabled_at`, `backup_codes_hashed`, `discord_id`, `discord_username`, `discord_linked_at`
  - Add associations: `has_many :account_roles`, `many_to_many :roles`

### Batch 1.4: RBAC Context Module
Create the authorization context for permission/role management.

- [ ] **1.4.1** Create `BezgelorDb.Authorization` context
  - `list_permissions/0` - Get all permissions
  - `list_permissions_by_category/0` - Get permissions grouped by category
  - `get_permission_by_key/1` - Lookup permission by key

- [ ] **1.4.2** Add role CRUD to `BezgelorDb.Authorization`
  - `list_roles/0` - Get all roles with permission counts
  - `get_role/1` - Get role by ID with permissions preloaded
  - `create_role/1` - Create new role
  - `update_role/2` - Update role name/description
  - `delete_role/1` - Delete role (fail if protected)
  - `set_role_permissions/2` - Replace role's permissions

- [ ] **1.4.3** Add account role functions to `BezgelorDb.Authorization`
  - `get_account_roles/1` - Get roles for an account
  - `get_account_permissions/1` - Get all permissions for account (union of roles)
  - `assign_role/3` - Assign role to account (with assigner tracking)
  - `remove_role/2` - Remove role from account
  - `has_permission?/2` - Check if account has specific permission

- [ ] **1.4.4** Add audit logging functions to `BezgelorDb.Authorization`
  - `log_action/5` - Create audit log entry
  - `list_audit_log/1` - Query audit log with filters
  - `get_account_audit_history/1` - Get actions by a specific admin

### Batch 1.5: Seed Permissions and Roles
Create seed data for permissions and default roles.

- [ ] **1.5.1** Create `priv/repo/seeds/permissions.exs`
  - Define all 40+ permissions from design doc
  - Organized by category (user_management, character_management, etc.)

- [ ] **1.5.2** Create `priv/repo/seeds/roles.exs`
  - Create Moderator role with permissions
  - Create Admin role with permissions
  - Create Super Admin role with all permissions
  - Mark all three as `protected: true`

- [ ] **1.5.3** Update `priv/repo/seeds.exs` to run permission/role seeds
  - Idempotent (safe to run multiple times)
  - Use `on_conflict: :nothing` for permissions
  - Log what was created

- [ ] **1.5.4** Run seeds and verify
  ```bash
  mix run priv/repo/seeds.exs
  ```

### Batch 1.6: SRP6 Web Authentication
Implement web login using existing SRP6 credentials.

- [ ] **1.6.1** Add `verify_password/2` to `BezgelorCrypto.Password`
  - Takes email, password, stored salt, stored verifier
  - Recomputes verifier and compares
  - Returns `true` or `false`

- [ ] **1.6.2** Create `BezgelorPortal.Auth` module
  - `authenticate/2` - Verify email/password via SRP6
  - `create_session/2` - Create Phoenix session for account
  - `logout/1` - Clear session

- [ ] **1.6.3** Create `BezgelorPortal.AuthController`
  - `GET /login` - Render login form
  - `POST /login` - Authenticate and redirect
  - `GET /logout` - Clear session and redirect

- [ ] **1.6.4** Create login LiveView (`LoginLive`)
  - Email and password form
  - Error handling (invalid credentials, account suspended)
  - "Remember me" checkbox (optional)

- [ ] **1.6.5** Create `BezgelorPortal.Plugs.RequireAuth`
  - Plug that checks session for logged-in user
  - Redirects to login if not authenticated
  - Loads current account into `conn.assigns`

- [ ] **1.6.6** Create `BezgelorPortal.Plugs.RequirePermission`
  - Plug that checks if current user has specific permission
  - Returns 403 if not authorized
  - Usage: `plug RequirePermission, :view_users`

- [ ] **1.6.7** Add routes and test login flow
  - Verify login with existing account works
  - Verify session persists across requests
  - Verify logout clears session

### Batch 1.7: Basic Navigation and Layout
Set up the authenticated app shell.

- [ ] **1.7.1** Create navigation component
  - Logo/brand
  - User dropdown (account settings, logout)
  - Admin link (if user has any admin permissions)

- [ ] **1.7.2** Create sidebar component (for admin)
  - Collapsible sections by category
  - Permission-aware (only show links user can access)

- [ ] **1.7.3** Create dashboard placeholder page
  - Welcome message with account info
  - Placeholder cards for future content

- [ ] **1.7.4** Wire up routes
  - `/` - Redirect to login or dashboard
  - `/login` - Login page
  - `/logout` - Logout action
  - `/dashboard` - Main dashboard (requires auth)

---

## Phase 2: User Portal

### Batch 2.1: Registration
Implement account registration with email verification.

- [ ] **2.1.1** Add `swoosh` and email dependencies to portal
  - Configure for dev (local adapter) and prod (SMTP/SendGrid)

- [ ] **2.1.2** Create `BezgelorDb.Accounts.create_account_with_verification/2`
  - Creates account with `email_verified_at: nil`
  - Generates verification token
  - Returns `{:ok, account, token}`

- [ ] **2.1.3** Create email verification token schema
  - `account_email_tokens` table with token, account_id, expires_at
  - Or use signed Phoenix tokens (stateless)

- [ ] **2.1.4** Create registration LiveView
  - Email, password, confirm password form
  - Password strength validation
  - Terms of service checkbox

- [ ] **2.1.5** Create verification email template
  - Welcome message
  - Verification link with token

- [ ] **2.1.6** Create email verification endpoint
  - `GET /verify/:token` - Verify email and redirect to login

- [ ] **2.1.7** Add rate limiting to registration
  - Prevent spam account creation
  - Use `hammer` or similar

### Batch 2.2: Account Management
Allow users to manage their account settings.

- [ ] **2.2.1** Create account settings LiveView
  - Tabbed interface: Profile, Security, Linked Accounts

- [ ] **2.2.2** Implement email change
  - Form to enter new email
  - Sends verification to new email
  - Updates only after verification

- [ ] **2.2.3** Implement password change
  - Requires current password
  - New password + confirmation
  - Invalidates other sessions (optional)

- [ ] **2.2.4** Implement account deletion
  - Confirmation modal
  - Must type email address to confirm
  - Soft delete (mark as deleted, anonymize after 30 days)

### Batch 2.3: TOTP Setup
Implement two-factor authentication.

- [ ] **2.3.1** Add TOTP secret encryption helpers
  - Use `cloak_ecto` or manual AES encryption
  - Store encrypted in `totp_secret_encrypted`

- [ ] **2.3.2** Create TOTP setup LiveView
  - Generate secret and QR code
  - Display backup codes (one-time generation)
  - Require code verification before enabling

- [ ] **2.3.3** Update login flow for TOTP
  - After password success, check if TOTP enabled
  - If yes, show TOTP code entry form
  - Validate code before creating session

- [ ] **2.3.4** Implement backup code redemption
  - Allow backup code instead of TOTP
  - Mark backup code as used (one-time)

- [ ] **2.3.5** Implement TOTP disable
  - Requires current password + TOTP code
  - Clears secret and backup codes

- [ ] **2.3.6** Enforce TOTP for admin roles
  - When assigning role, check if TOTP enabled
  - If not, require setup before role takes effect

### Batch 2.4: Character Viewer
Read-only view of user's characters.

- [ ] **2.4.1** Create characters list LiveView
  - Grid/list of characters with avatar, name, level, class
  - Click to view details

- [ ] **2.4.2** Create character detail LiveView
  - Basic info: name, level, race, class, faction
  - Location: zone, coordinates, last online
  - Play time statistics

- [ ] **2.4.3** Add inventory tab
  - Equipped items display
  - Bag contents (paginated)
  - Bank contents (paginated)

- [ ] **2.4.4** Add currency display
  - Gold, elder gems, renown, prestige
  - Other game currencies

- [ ] **2.4.5** Add guild info
  - Guild name and rank
  - Link to guild (if we add guild pages later)

- [ ] **2.4.6** Add tradeskills display
  - Profession levels
  - Known recipes count

- [ ] **2.4.7** Add collections display
  - Mounts, pets, costumes owned
  - Achievement points summary

- [ ] **2.4.8** Implement character deletion
  - Confirmation modal with character name typing
  - Calls existing soft-delete function

---

## Phase 3: Admin Panel - Core

### Batch 3.1: Admin Layout
Create the admin section structure.

- [ ] **3.1.1** Create admin layout (`admin.html.heex`)
  - Sidebar navigation
  - Breadcrumbs
  - Permission-aware menu

- [ ] **3.1.2** Create admin dashboard LiveView
  - Quick stats cards (online players, accounts, zones)
  - Recent admin actions (from audit log)
  - Server status indicator

- [ ] **3.1.3** Set up admin routes with permission checks
  - `/admin` - Dashboard (any admin permission)
  - Nested routes per section

### Batch 3.2: User Management
Admin tools for managing user accounts.

- [ ] **3.2.1** Create user search LiveView
  - Search by email, character name, account ID
  - Results table with pagination
  - Quick actions column

- [ ] **3.2.2** Create user detail LiveView
  - Account info, registration date, last login
  - Email verification status
  - TOTP status
  - Discord link status

- [ ] **3.2.3** Implement password reset action
  - Generate reset token
  - Send email with reset link
  - Log action to audit log

- [ ] **3.2.4** Implement ban/suspend actions
  - Ban modal: reason, duration (or permanent)
  - Creates `AccountSuspension` record
  - Kicks user if online
  - Logs to audit log

- [ ] **3.2.5** Implement unban action
  - Remove active suspension
  - Log to audit log

- [ ] **3.2.6** Implement role assignment
  - Show current roles
  - Add/remove roles (with permission check)
  - Enforce TOTP requirement for admin roles
  - Log to audit log

### Batch 3.3: Character Management (Admin)
Admin tools for viewing and modifying characters.

- [ ] **3.3.1** Create character search LiveView
  - Search by name
  - Browse by account
  - Results with owner info

- [ ] **3.3.2** Create admin character detail LiveView
  - Full character inspection
  - All tabs from user view
  - Plus: modification actions

- [ ] **3.3.3** Implement item grant action
  - Item ID lookup/search
  - Quantity input
  - Sends via system mail
  - Logs to audit log

- [ ] **3.3.4** Implement currency grant action
  - Select currency type
  - Amount input (positive or negative)
  - Direct modification
  - Logs to audit log

- [ ] **3.3.5** Implement level modification
  - Set level directly
  - Or add XP amount
  - Logs to audit log

- [ ] **3.3.6** Implement teleport action
  - Zone selector
  - Coordinate input (or named locations)
  - Only works if character offline (or send command if online)
  - Logs to audit log

- [ ] **3.3.7** Implement character rename
  - New name input with validation
  - Checks name availability
  - Logs to audit log

- [ ] **3.3.8** Implement character delete/restore
  - Soft delete (same as user self-delete)
  - Restore from deleted
  - Both log to audit log

### Batch 3.4: Audit Log Viewer
View admin action history.

- [ ] **3.4.1** Create audit log LiveView
  - Filterable by admin, action type, target, date range
  - Paginated results
  - Detail expansion for `details` JSON

- [ ] **3.4.2** Implement export functionality
  - Export to CSV
  - Export to JSON
  - Date range selection

---

## Phase 4: Admin Panel - Advanced

### Batch 4.1: Economy Tools
Admin tools for economy management.

- [ ] **4.1.1** Create economy overview LiveView
  - Total gold in circulation
  - Daily gold generated (quest rewards, loot, etc.)
  - Daily gold removed (repairs, vendors, AH fees)
  - Charts for trends

- [ ] **4.1.2** Create transaction log viewer
  - Search by account, character, type
  - Filter by amount range, date range
  - Show source and destination

- [ ] **4.1.3** Create gift tools LiveView
  - Send currency to character
  - Send item(s) to character
  - Batch sending option
  - All logged to audit

### Batch 4.2: Event Management
Admin tools for public events and world bosses.

- [ ] **4.2.1** Create events overview LiveView
  - List active/scheduled events
  - Event status and participants

- [ ] **4.2.2** Implement event controls
  - Start event manually
  - Stop/cancel event
  - Schedule future event

- [ ] **4.2.3** Create world boss controls
  - List world bosses with spawn status
  - Force spawn
  - Reset spawn timer

- [ ] **4.2.4** Create creature spawn tool
  - Creature ID lookup
  - Zone and position selection
  - Spawn with optional despawn timer

### Batch 4.3: Instance Management
Admin tools for dungeons and raids.

- [ ] **4.3.1** Create instances overview LiveView
  - List all active instances
  - Instance type, players, duration
  - Boss status (alive/dead)

- [ ] **4.3.2** Create instance detail view
  - Player list
  - Loot dropped
  - Instance timeline

- [ ] **4.3.3** Implement instance controls
  - Force close instance
  - Teleport players out

- [ ] **4.3.4** Create lockout management
  - Search player lockouts
  - Reset specific lockouts
  - Bulk reset option

### Batch 4.4: Role Management UI
Super admin role management.

- [ ] **4.4.1** Create roles list LiveView
  - All roles with permission counts
  - Protected badge for built-in roles
  - User count per role

- [ ] **4.4.2** Create role create/edit LiveView
  - Name and description fields
  - Permission checkbox grid by category
  - Save/cancel actions

- [ ] **4.4.3** Implement role deletion
  - Confirmation modal
  - Check for protected status
  - Warn about affected users
  - Reassign or remove from users

### Batch 4.5: Server Operations
Admin tools for server management.

- [ ] **4.5.1** Create server operations LiveView
  - Maintenance mode toggle
  - MOTD editor
  - Server uptime display

- [ ] **4.5.2** Create broadcast message tool
  - Message input with formatting
  - Target selection (all, zone, faction)
  - Send button with confirmation

- [ ] **4.5.3** Create connected players view
  - List all online players
  - Zone, character, connection time
  - Kick individual or kick all

- [ ] **4.5.4** Create zone management view
  - List active zone instances
  - Player count per zone
  - Restart zone option

---

## Phase 5: Analytics Dashboard

### Batch 5.1: Dashboard Structure
Set up the real-time analytics dashboard.

- [ ] **5.1.1** Create analytics layout
  - Grid-based card layout
  - Responsive design
  - Auto-refresh indicators

- [ ] **5.1.2** Set up PubSub for live updates
  - Define topics for each metric category
  - Create broadcaster GenServer
  - Subscribe in LiveView

- [ ] **5.1.3** Create reusable stat card component
  - Title, value, change indicator
  - Optional sparkline chart
  - Click for detail modal

### Batch 5.2: Player Statistics
Real-time player metrics.

- [ ] **5.2.1** Implement registered accounts counter
  - Total count from DB
  - Daily/weekly growth

- [ ] **5.2.2** Implement online players counter
  - Query from `bezgelor_world` player registry
  - Real-time updates via PubSub

- [ ] **5.2.3** Implement players by zone display
  - Table or map view
  - Zone name, player count
  - Click to see player list

- [ ] **5.2.4** Implement peak concurrent tracking
  - Track daily/weekly/monthly peaks
  - Display with timestamps

### Batch 5.3: BEAM/OTP Metrics
Elixir runtime metrics.

- [ ] **5.3.1** Implement memory breakdown display
  - Total memory
  - Process memory
  - Atom memory
  - Binary memory
  - ETS memory
  - Use `:erlang.memory/0`

- [ ] **5.3.2** Implement process count display
  - Total process count
  - Trend over time

- [ ] **5.3.3** Implement scheduler utilization
  - Per-scheduler utilization %
  - Use `:scheduler.utilization/1`

- [ ] **5.3.4** Implement message queue monitoring
  - Key processes with high queue lengths
  - Alert threshold indicator

### Batch 5.4: Game Metrics
Game-specific statistics.

- [ ] **5.4.1** Implement active zones counter
  - Count of spawned zone instances

- [ ] **5.4.2** Implement active instances counter
  - Dungeon/raid instance count
  - Average instance duration

- [ ] **5.4.3** Implement queue metrics
  - Dungeon finder queue size
  - PvP queue sizes
  - Average wait times

- [ ] **5.4.4** Implement economy metrics
  - Total gold in circulation
  - Daily gold delta
  - AH volume

### Batch 5.5: System Metrics
OS-level metrics.

- [ ] **5.5.1** Enable `:os_mon` application
  - Add to extra_applications
  - Configure in config

- [ ] **5.5.2** Implement CPU usage display
  - Overall CPU %
  - Per-core breakdown (optional)

- [ ] **5.5.3** Implement system memory display
  - Total/used/free RAM
  - Swap usage

- [ ] **5.5.4** Implement uptime display
  - System uptime
  - Application uptime

---

## Phase 6: Integrations

### Batch 6.1: Discord OAuth
Link Discord accounts.

- [ ] **6.1.1** Add `ueberauth` and `ueberauth_discord` deps
  - Configure Discord OAuth app credentials

- [ ] **6.1.2** Create Discord link flow
  - Button to initiate OAuth
  - Callback to save Discord ID and username
  - Display linked status

- [ ] **6.1.3** Create Discord unlink action
  - Confirmation modal
  - Clear Discord fields

- [ ] **6.1.4** (Future) Add in-game badge for linked accounts
  - Check Discord link status on character load
  - Grant badge/title

### Batch 6.2: OpenTelemetry
Instrument the application.

- [ ] **6.2.1** Add OpenTelemetry dependencies
  - `opentelemetry`, `opentelemetry_exporter`
  - `opentelemetry_phoenix`, `opentelemetry_ecto`

- [ ] **6.2.2** Configure OpenTelemetry
  - Development: console exporter
  - Production: OTLP exporter (env-configured)

- [ ] **6.2.3** Add Phoenix instrumentation
  - HTTP request spans
  - LiveView event spans

- [ ] **6.2.4** Add Ecto instrumentation
  - Database query spans

- [ ] **6.2.5** Add custom game telemetry
  - Player login/logout events
  - Combat events
  - Economy events

- [ ] **6.2.6** Create telemetry dashboard link
  - Link to external service (Honeycomb/Jaeger)
  - Or embedded trace viewer (if self-hosted)

### Batch 6.3: Email Service
Production email sending.

- [ ] **6.3.1** Configure Swoosh for production
  - SMTP or SendGrid adapter
  - Environment variable configuration

- [ ] **6.3.2** Create email templates
  - Email verification
  - Password reset
  - Account suspended notification
  - Admin action notifications (optional)

- [ ] **6.3.3** Add email sending to relevant flows
  - Registration verification
  - Email change verification
  - Password reset request

---

## Testing Strategy

### Unit Tests
- `BezgelorDb.Authorization` context functions
- `BezgelorCrypto.Password.verify_password/2`
- TOTP generation and verification
- Permission checking logic

### Integration Tests
- Login flow (success, failure, suspended)
- Registration and email verification
- TOTP setup and login with TOTP
- Admin actions with audit logging
- Role assignment with TOTP enforcement

### LiveView Tests
- Form submissions
- Real-time updates
- Permission-based rendering

---

## Deployment Considerations

### Environment Variables
```bash
# Portal
PORTAL_PORT=4001
SECRET_KEY_BASE=...
TOTP_ENCRYPTION_KEY=...

# Email
SMTP_HOST=...
SMTP_PORT=587
SMTP_USER=...
SMTP_PASSWORD=...

# Discord OAuth
DISCORD_CLIENT_ID=...
DISCORD_CLIENT_SECRET=...

# OpenTelemetry
OTEL_EXPORTER_OTLP_ENDPOINT=https://api.honeycomb.io
OTEL_EXPORTER_OTLP_HEADERS=x-honeycomb-team=...
```

### Database
- Run migrations before deploy
- Seed permissions (idempotent)
- Create initial super admin account manually

### Monitoring
- Configure OpenTelemetry exporter
- Set up alerts for error rates
- Monitor BEAM metrics
