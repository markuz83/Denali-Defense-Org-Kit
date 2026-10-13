# Demo Org Data Model

Government contracting demo org: capture → award → project delivery → service delivery and support.

This document describes the org **as built** (`denali-sb`, checked against the live org on 2026-10-06). Where the original design and the org differ, the org wins. Anything designed but not built is marked **Not built**, so the gap is visible instead of silently dropped.

**Contents**
1. Architecture: relationships, rollups, standard features, automation, decisions, supplier portal (designed, not built), deploy order
2. Global value sets
3. Objects: Account · Contact · Opportunity · Contract · Project__c · Deliverable__c · Deliverable_Update__c · Supplier_Assignment__c · Project_Resource__c · Service_Engagement__c · Engagement_Milestone__c · Case · Risk__c · Asset / Product2

---

## 1. Architecture

### Relationship map

```
            ┌──(Lost To / Incumbent: competitor Accounts)──┐
Account ──< Opportunity ──(Source Opportunity)── Contract  │
   │            │                                   │      │
   │            └──< Asset (Source Opportunity)     │
   │                          ┌─────────────────────┼─────────────────────┐
   │                          │ (Lookup, required)  │ (Lookup)            │
   │                       Project__c         Service_Engagement__c ──(Lookup)── Entitlement
   │          ┌───────────────┼───────────────┐     │                    │
   │      (Lookup, req)     (M-D)           (M-D)  (M-D)             (Lookup)
   │     Deliverable__c  Supplier_       Project_  Engagement_          Case
   │          │          Assignment__c   Resource__c Milestone__c
   │        (M-D)            │               │
   │   Deliverable_Update__c └─ Account      └─ User
   │
   └── Risk__c (lookups to Account / Contract / Project / Deliverable)
```

### Relationship decisions

| Child → Parent | Type | Why |
| --- | --- | --- |
| Project → Contract | Lookup (required, delete **Restrict**) | Keeps the master-detail chain short (Salesforce caps multilevel M-D depth) and leaves room for Project → Deliverable → Update. Contract-level rollups run through DLRS. |
| Deliverable → Project | **Lookup (required, delete Restrict)** | Built for supplier access through a sharing set on `Deliverable__c.Supplier__c`. Sharing sets can't target detail objects (the parent controls their sharing), so Deliverable can't be M-D. Project's deliverable rollups run through DLRS. |
| Deliverable_Update → Deliverable (M-D sharing setting) | **Read Only** | Read access on the Deliverable is enough to create updates against it. This is what would let a read-only supplier submit. |
| Deliverable_Update → Deliverable | Master-Detail | Updates have no life without the deliverable. |
| Supplier_Assignment → Project | Master-Detail | Native rollup of subcontract value. |
| Supplier_Assignment → Account | Lookup (required, delete Restrict) | Making Account a second master means Account deletes cascade and users need access to both parents. Lookup is fine for a demo. |
| Project_Resource → Project | Master-Detail | |
| Project_Resource → User | Lookup | User can't be a master. Required by validation rule, not at field level. |
| Engagement_Milestone → Service_Engagement | Master-Detail | Native "Next Milestone Date" rollup. |
| Service_Engagement → Contract | Lookup | |
| Risk → Account/Contract/Project/Deliverable | Lookups | A risk can live at any level; flow fills the parents upward. |
| Case → Service_Engagement / Project / Deliverable | Lookups | |
| Opportunity → Account (Lost To, Incumbent) | Lookups, filtered to competitors | Win/loss by competitor; DLRS rolls lost deals up to the competitor Account. |
| Asset → Opportunity (Source Opportunity) | Lookup | The deal that created the installed-base asset. |

Lookups not listed above use delete **Set Null**.

### Rollup strategy

**Native roll-up summary (M-D parents):**
- Project: Subcontracted Value, Team Size
- Service_Engagement: Next Milestone Date

**DLRS (lookup parents).** The DLRS-vs-Flow decision went to DLRS. 21 rollups, all **Realtime**, all active (`dlrs/`):

| Parent | Field | Operation | Child (relationship field) | Criteria |
| --- | --- | --- | --- | --- |
| Account | Total_Contract_Value__c | SUM Contract_Value__c | Contract (AccountId) | |
| Account | Active_Contract_Value__c | SUM Contract_Value__c | Contract (AccountId) | `Status = 'Activated'` |
| Account | Contract_Backlog__c | SUM Total_Backlog__c | Contract (AccountId) | `Status = 'Activated'` |
| Account | Active_Projects__c | COUNT | Project__c (Account__c) | `Status__c = 'In Progress'` |
| Account | At_Risk_Projects__c | COUNT | Project__c (Account__c) | `Health__c = 'Red' AND Status__c NOT IN ('Complete','Cancelled')` |
| Account | Open_Deliverables__c | COUNT | Deliverable__c (Account__c) | `Status__c NOT IN ('Complete','Cancelled')` |
| Account | At_Risk_Deliverables__c | COUNT | Deliverable__c (Account__c) | `Is_At_Risk__c = true` |
| Account | Open_Cases__c | COUNT | Case (AccountId) | `IsClosed = false` |
| Account | Deals_Lost_To__c | COUNT | Opportunity (Lost_To__c) | `IsClosed = true AND IsWon = false` |
| Account | Bookings_Lost_To__c | SUM Amount | Opportunity (Lost_To__c) | `IsClosed = true AND IsWon = false` |
| Contract | Revenue_Recognized__c | SUM Revenue_Recognized__c | Project__c (Contract__c) | |
| Contract | Actual_Cost__c | SUM Actual_Cost__c | Project__c (Contract__c) | |
| Contract | Forecast_Cost__c | SUM Forecast_Cost__c | Project__c (Contract__c) | |
| Contract | Revenue_Allocation__c | SUM Revenue_Allocation__c | Project__c (Contract__c) | |
| Project__c | Deliverables__c | COUNT | Deliverable__c (Project__c) | |
| Project__c | Deliverables_Complete__c | COUNT | Deliverable__c (Project__c) | `Status__c = 'Complete'` |
| Project__c | Deliverables_at_Risk__c | COUNT | Deliverable__c (Project__c) | `Is_At_Risk__c = true` |
| Project__c | Revenue_Recognized__c | SUM Revenue_Milestone__c | Deliverable__c (Project__c) | `Acceptance_Status__c = 'Accepted'` |
| Project__c | Revenue_at_Risk__c | SUM Revenue_Milestone__c | Deliverable__c (Project__c) | `Is_At_Risk__c = true` |
| Project__c | Open_Risks__c | COUNT | Risk__c (Project__c) | `Status__c NOT IN ('Closed','Realized')` |
| Service_Engagement__c | Cases_Open__c | COUNT | Case (Service_Engagement__c) | `IsClosed = false` |

DLRS recalculates both the old and the new parent when a child moves (e.g., a Deliverable reassigned to another Project), which hand-built flows would have to handle themselves.

**Scheduled Apex, not DLRS:** `Service_Engagement__c.SLA_Breaches__c` comes from `SlaBreachRollup` (`optional/`), which runs hourly as the scheduled job **Denali SLA Breach Rollup** (set up by `scripts/apex/10_schedule_sla_breach_rollup.apex`). It checks `Case.SLA_Breached__c` on each case with at least one violated milestone (`CaseMilestone.IsViolated`, open or completed late), clears it when none is left, and counts those cases per engagement. Violations happen as time passes, not on a record save, so a realtime rollup would never fire, and DLRS can't filter on `Case.MilestoneStatus`. `03_recalculate_rollups.apex` calls the same class.

**Rule of thumb for rollup filters:** criteria are AND-only and can't use formulas with TODAY(). Any OR logic goes into a formula checkbox on the child (e.g., `Is_At_Risk__c`), and the rollup filters on that.

### Standard features replacing custom fields

All of these are in place.

| Custom field in draft | Use instead |
| --- | --- |
| Case: SLA Target, SLA Status | Entitlements + Milestones (`MilestoneStatus`, Case Milestones related list) |
| Case: Escalated | Standard `IsEscalated` |
| Service_Engagement: SLA picklist | Lookup to an Entitlement whose process carries the SLA timers |
| Contract: Contract Number | Standard `ContractNumber` is already an auto-number, so the custom field is **Award Number** |
| Contract: End Date (entered) | Standard `EndDate` is calculated from Start Date + Contract Term (months) |
| Account: Account Manager | Account Owner |
| Deliverable_Update: Attachment | Files related list (not a field type) |

### Naming

The draft's `Service_Milestone__c` was built as **Engagement_Milestone__c** so it doesn't collide conceptually with Service Cloud's standard Milestones (MilestoneType, CaseMilestone, EntitlementMilestone).

### Automation inventory

All flows below are active record-triggered flows. The numbers match each flow's description in the org.

| # | Flow (API name) | Object / Trigger | Does |
| --- | --- | --- | --- |
| 1 | Opportunity_Create_Contract_on_Win | Opportunity, after update → Closed Won, Create Contract on Win checked, has Account, no ContractId | Creates a Draft Contract carrying Vehicle, Acquisition Type, Prime/Sub, Contract Type, ECV → Contract Value, Estimated Margin → Original Margin, Program Manager, Source Opportunity. Skips if a Contract already points at the Opportunity, and skips deals already linked to a Contract (task orders, mods, option exercises grow that contract instead) |
| 2 | Project_Defaults | Project, before save | Account ← Contract.AccountId |
| 3 | Deliverable_Defaults | Deliverable, before save | Contract/Account ← Project; stamps Acceptance Date the first time it's Accepted |
| 4 | Deliverable_Update_Intake | Deliverable_Update, before create | Fills blank Project, Supplier (from the Deliverable), Submitted By (`$User.ContactId`), Submitted Date |
| 5 | Deliverable_Update_Notify_PM | Deliverable_Update, after create, **async path** | Custom notification (bell + mobile) + email to the Project Manager. Async so a notification failure never blocks the submission |
| 6 | Deliverable_Update_Review | Deliverable_Update, after update → Accepted / Needs Clarification / Rejected | Accepted: pushes % complete, forecast date, status, customer action, blockers to the Deliverable and stamps Latest Update Date. Needs Clarification / Rejected: emails the submitter the Reviewer Comments (async) |
| 7 | Deliverable_Update_Review_Stamp | Deliverable_Update, before update | Reviewed By / Review Date when review status changes to Accepted, Needs Clarification, or Rejected |
| 8 | Case_Entitlement | Case, before save, Service Engagement set | EntitlementId ← Service_Engagement__r.Entitlement__c |
| 9 | Case_Priority_Matrix | Case, before save, Severity + Customer Impact set and new/changed | Priority from Severity × Customer Impact (matrix under Case) |
| 10 | Case_Create_Risk | Case, after save, Deliverable set and Severity becomes Sev 1/2 | Creates an Identified, Technical Risk__c on the Deliverable with what the case establishes: Revenue at Risk (the Deliverable's revenue milestone), Risk Owner (the Project Manager), Target Resolution Date (the Deliverable's due date) and Consequence (Sev 1: 5 - Severe, Sev 2: 4 - Significant). Likelihood is left for the PM, so Risk Score and Severity stay blank until it's scored |
| 11 | Risk_Parents | Risk, before save | Fills Project/Contract/Account upward from the lowest parent set |
| 12 | Contract_Option_Reminder | Contract, Activated with Next Option Date and Program Manager; scheduled path **60 days before** Next Option Date | Task to the Program Manager (immediately if the date is already inside the window) |
| 13 | Engagement_Milestone_Renewal_Opp | Engagement_Milestone, Type = Renewal, not Complete/Cancelled; scheduled path **90 days before** Due Date | Creates an Opportunity: Option Exercise if the Contract still has a Next Option Date, else Recompete. Amount = Service Engagement ACV, Owner = Milestone Owner then Service Owner. Skips if an open Opportunity is already linked to the Contract |
| 14 | Project_Resource_Defaults | Project_Resource, before save | Manager ← Employee's `ManagerId`; Unique Key = Project Id + Employee Id |
| 15 | Case_Complete_Milestones | Case, after update, Status changed | Completes First Response when a case moves on from New, and all open milestones when it closes |
| 16 | Case_SLA_Clock | Case, before save, new or Status changed | Sets `SlaStartDate` on new cases; sets `IsStopped` while **Waiting on Customer**. Waiting on Supplier keeps the clock running, so supplier delays count against Denali's SLA |

**Unnumbered automation (added after the original design):**

| Flow / process | Object / Trigger | Does |
| --- | --- | --- |
| Opportunity_Exercise_Option | Opportunity, after update → Closed Won, Type = Option Exercise, linked to a Contract | Exercises the option on that Contract: Current Period up a year, Next Option Date a year later (cleared after the last option year or at the contract end), Funded Value + Amount. Contract Value only rises if the new funding would exceed it. Skips a contract already in Option Year 4 |
| Opportunity_Create_Assets_on_Win | Opportunity, after update → Closed Won | `OpportunityAssets` Apex creates an Asset per product line whose Product has Track as Asset checked |
| Opportunity_Margin_Approval_Reset | Opportunity, before update | Clears Margin Approval Status when Estimated Margin or Contract Type changes after a decision |
| Opportunity_Pricing_Rationale (`ai/`) | Opportunity, after save, async; open deal crosses below Margin Floor | Einstein prompt template drafts Pricing Rationale for the approver |
| Scheduled Apex `SlaBreachRollup` (`optional/`) | Hourly (job **Denali SLA Breach Rollup**) | Flags each case with a violated SLA milestone (Case SLA Breached) and recounts them into each Service Engagement's SLA Breaches |
| Opportunity_Refresh_Account_Plan_Measures (`account-plans/`) | Opportunity, after update, Stage or Amount changed | `AccountPlanMeasureRefresh` Apex recalculates linked Sales Account Plan measures |
| Approval process **Margin Exception** | Opportunity | Below-floor deals go to a manually chosen Pricing Review approver; the `Margin_Approval_Required` validation rule blocks proposal stages and Closed Won until Approved |

**Designed but not built:**
- A before-save flow filling `Service_Engagement__c.Account__c` from the Contract. It's set by hand or by the seed script.
- A before-save flow filling `Engagement_Milestone__c` Contract/Account from the Service Engagement.
- One-per-parent enforcement for `Contact.Primary_Contact__c` and `Supplier_Assignment__c.Primary_Supplier__c`. Left to convention.
- A flow setting `Account.Customer_Health__c` to the worst health of active Contracts/Projects. Manual.
- A flow setting `Project__c.Risk_Level__c` from the highest open Risk severity. Manual.
- Stamping `Risk__c.Closed_Date__c` when Status → Closed or Realized. Manual.
- Entitlement milestone actions (75% warning, violation → escalate). The processes have none.

### Decisions

1. **Resolved: Deliverable → Project is a Lookup.** Suppliers were to submit Deliverable Updates through Experience Cloud, and the sharing set needs Deliverable to control its own access (see Supplier portal). A Project↔Deliverable junction was considered and rejected: the relationship is one-to-many, and a junction would bring back neither native rollups nor simpler sharing.
2. **Resolved: custom Service_Engagement__c over standard ServiceContract.** The custom object carries Service Type, Service Level and Health, and gets its SLA timers from an Entitlement lookup. ServiceContract isn't used.
3. **Resolved: DLRS** for every lookup rollup (21 Realtime rules; see Rollup strategy).

### Supplier portal (Experience Cloud): designed, **not built**

The org has no Experience Cloud site, no Supplier Portal User profile, and no sharing set. It's on the README roadmap. What's already in place for it:

- External OWD: Deliverable__c **Private**, Deliverable_Update__c **Controlled by Parent**, Account **Private**, Contact **Controlled by Parent**.
- Deliverable_Update → Deliverable M-D sharing setting is **Read Only**.
- The `Supplier_Edit_Lock` validation rule is active on Deliverable_Update__c.
- Flow #4 fills Submitted By from `$User.ContactId`.
- Flow #5 can read Project → Project Manager for a portal submitter, because record-triggered flows run in system context without sharing.

#### Access model (to build)

| Layer | Setting |
| --- | --- |
| License / profile | Customer Community license (the org has Customer Community User and Community Plus profiles to clone); name the clone **Supplier Portal User**. Sharing sets were built for these high-volume licenses. If you use Partner or Customer Community Plus instead, check whether the Sharing Sets setup page lets you select that profile. If it doesn't, you're into sharing rules or Apex managed sharing. |
| Sharing set | Profile: Supplier Portal User. Object: Deliverable__c. Match `User.AccountId` ↔ `Deliverable__c.Supplier__c`. Access: Read Only |
| Object permissions | Deliverable__c: Read. Deliverable_Update__c: Read, Create, Edit. No access to Project, Contract, Opportunity, Risk, Supplier_Assignment |
| FLS: Deliverable | **Hidden:** Revenue Milestone, Revenue at Risk, Is At Risk, Risk Level, Risk Description, Project, Contract, Account, Health. **Read-only:** Name, Number, Type, Description, Status, Due Date, Forecast Completion Date, Percent Complete, Acceptance Status, Requires Customer Action |
| FLS: Deliverable_Update | **Read-only:** Internal Review Status, Reviewer Comments (so suppliers can see clarification requests), Supplier, Submitted By, Submitted Date. **Hidden:** Reviewed By, Review Date, Project |

#### Supplier edit lock (active on Deliverable_Update__c)

```
AND(
  NOT(ISNEW()),
  NOT(ISBLANK($User.ContactId)),
  NOT(ISPICKVAL(PRIORVALUE(Internal_Review_Status__c), "Pending"))
)
```
Once review starts, suppliers can't edit an update. If a reviewer marks it Needs Clarification, the supplier responds with a new update, which keeps a clean audit trail.

#### Site build (to build)

- Template: **Customer Service** (Aura) is fastest for a demo because the standard record detail, list, and related list components work out of the box. **Build Your Own (LWR)** is where Salesforce is investing, but it needs more assembly.
- Members: the Supplier Portal User profile.
- Pages: Home with a "My Open Deliverables" list view (Status NOT IN Complete, Cancelled, sorted by Due Date). Deliverable detail page with the Updates related list, its New button, and Files.
- Demo users: enable Contacts on two supplier Accounts as external users, then log in as each to show that neither can see the other's deliverables.

### Deploy order

The README's package table is the source of truth. In short: `force-app/` (data model, automation, analytics, pages) → `optional/` (standard picklist values, sales processes and record types, entitlement process and milestone types, Case path, Knowledge field, Case flows, SLA Breaches job) → `ai/` → `dlrs/` (needs the DLRS package) → `account-plans/` → `persona-apps/` → `standard-layouts/` → `scripts/apex/` (grant access, seed data, recalculate rollups, schedule the SLA Breaches job).

### If CPQ ever goes in this org

CPQ contracting and renewals run through the standard Contract object. The org has **no Contract record types**, so the government-contract validation rule (`Original_Margin_Locked`) and Flow #1 apply to every Contract. If CPQ arrives, add a **Government Award** record type and put those rules behind it so CPQ-generated contracts aren't blocked.

---

## 2. Global value sets

All 12 exist in the org with these values.

| Name                  | Values                                                                                                            | Used On                                                                                                                                                                        |
| --------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Health_Status         | Green; Yellow; Red                                                                                                | Account.Customer_Health__c; Contract.Contract_Health__c; Project__c.Health__c; Deliverable__c.Health__c; Deliverable_Update__c.Supplier_Health__c; Service_Engagement__c.Health__c; Engagement_Milestone__c.Health__c |
| Risk_Level            | Low; Medium; High; Critical                                                                                       | Project__c.Risk_Level__c; Deliverable__c.Risk_Level__c *(Risk__c uses a formula Severity field instead; formulas can't bind to a value set)*                                   |
| Priority              | Low; Medium; High; Critical                                                                                       | Deliverable__c.Priority__c; Opportunity.Customer_Priority__c *(Case.Priority is standard and can't use a GVS; its values match manually)*                                     |
| Contract_Type         | Fixed Price; Time & Materials; Cost Plus                                                                          | Contract; Opportunity (expected type, copied to Contract on win; also drives Margin Floor)                                                                                    |
| Prime_Subcontract     | Prime; Subcontract                                                                                                | Opportunity; Contract                                                                                                                                                          |
| Contract_Vehicle      | IDIQ; GWAC; GSA Schedule; BPA; BOA; Direct Contract                                                               | Opportunity; Contract *("Subcontract" left out; Prime_Subcontract covers it)*                                                                                                 |
| Service_Type          | Managed Services; Technical Support; Maintenance; Sustainment; Cybersecurity; Training; Logistics; Infrastructure | Service_Engagement__c                                                                                                                                                          |
| Deliverable_Type      | Hardware; Software; Documentation; Training; Integration; Testing; Certification; Maintenance                     | Deliverable__c                                                                                                                                                                 |
| Deliverable_Status    | Not Started; In Progress; Blocked; Submitted; Complete; Cancelled                                                 | Deliverable__c.Status__c; Deliverable_Update__c.Reported_Status__c                                                                                                             |
| Acceptance_Status     | Not Submitted; Pending Review; Accepted; Conditionally Accepted; Rejected                                         | Deliverable__c.Acceptance_Status__c; Engagement_Milestone__c.Customer_Acceptance__c                                                                                            |
| Risk_Category         | Schedule; Cost; Supplier; Technical; Customer; Staffing; Compliance; Security; Quality                            | Risk__c *(only Risk has this field; "Supplier" is an Account role, not an object)*                                                                                            |
| Acquisition_Type      | Competitive; Sole Source; Follow-On; OTA                                                                          | Opportunity; Contract                                                                                                                                                          |

#### Notes

- "Follow-On" overlaps with Opportunity Type = Recompete. It was kept for the acquisition-method view; "Small Business Set-Aside" is the alternative if you want more gov flavor.
- GVS-bound picklists are automatically restricted.

---

## 3. Objects

The org also has **multiple currencies** on (USD is the only active currency, so every object carries `CurrencyIsoCode`) and **Person Accounts**. Objects from the trial org's template (`Customer_Order__c`, `Return_Order__c`, `BenefitManagementRecertification__c`, the Data Quality Score/Description formulas on Account, Contact, Opportunity, Contract and Case, and Contact's Loyalty Status) aren't part of this model.

---

### 3.1 Account

Record types: **Business Account** and **Person Account**. Person Accounts mirror Contact's custom fields as `__pc` fields. Account Teams are on. Internal OWD Read/Write, external Private.

#### Standard fields

| Field            | API Name        | Type            | Values / Notes                                                                                                    |
| ---------------- | --------------- | --------------- | ----------------------------------------------------------------------------------------------------------------- |
| Account Name     | Name            | Text            | Company name                                                                                                      |
| Account Type     | Type            | Picklist        | Salesforce defaults (Analyst … Other). **Hide from layouts.** Account Role + Account Status replace it             |
| Industry         | Industry        | Picklist        | Defense; Aerospace; Federal Civilian; Intelligence Community; State & Local Government; Technology; Manufacturing; Logistics (`optional/` value set) |
| Parent Account   | ParentId        | Lookup(Account) | Agency hierarchy (e.g., DoD → Army → PEO)                                                                          |
| Account Owner    | OwnerId         | Lookup(User)    | Serves as Account Manager                                                                                         |
| Phone            | Phone           | Phone           |                                                                                                                   |
| Website          | Website         | URL             |                                                                                                                   |
| Billing Address  | BillingAddress  | Address         |                                                                                                                   |
| Shipping Address | ShippingAddress | Address         |                                                                                                                   |
| Description      | Description     | Long Text       |                                                                                                                   |

#### Custom fields

| Field                 | API Name                   | Type                    | Values / Formula / Source                                                                  |
| --------------------- | -------------------------- | ----------------------- | ------------------------------------------------------------------------------------------ |
| Account Role          | Account_Role__c            | Multi-Select Picklist   | Customer; Supplier; Partner; Competitor                                                    |
| Roles                 | Role_Summary__c            | Formula (Text)          | Space-separated list of the selected roles, for list views and the header                 |
| Is Customer           | Is_Customer__c             | Formula (Checkbox)      | `INCLUDES(Account_Role__c, "Customer")`, for lookup filters, rollup filters, reports      |
| Is Supplier           | Is_Supplier__c             | Formula (Checkbox)      | `INCLUDES(Account_Role__c, "Supplier")`                                                    |
| Is Competitor         | Is_Competitor__c           | Formula (Checkbox)      | `INCLUDES(Account_Role__c, "Competitor")`                                                  |
| Account Status        | Account_Status__c          | Picklist                | Prospect; Active; Inactive                                                                 |
| Customer Tier         | Customer_Tier__c           | Picklist                | Strategic; Key; Standard                                                                   |
| Customer Health       | Customer_Health__c         | Picklist (GVS)          | Health_Status. Manual (the worst-health flow wasn't built)                                 |
| Strategic Account     | Strategic_Account__c       | Formula (Checkbox)      | `ISPICKVAL(Customer_Tier__c, "Strategic")`, derived so it can't drift from Tier           |
| Government Account    | Government_Account__c      | Checkbox                |                                                                                            |
| Total Contract Value  | Total_Contract_Value__c    | Currency                | DLRS: SUM Contract.Contract_Value__c                                                       |
| Active Contract Value | Active_Contract_Value__c   | Currency                | DLRS: SUM Contract.Contract_Value__c WHERE Status = Activated                              |
| Contract Backlog      | Contract_Backlog__c        | Currency                | DLRS: SUM Contract.Total_Backlog__c WHERE Status = Activated                               |
| Active Projects       | Active_Projects__c         | Number(18,0)            | DLRS: COUNT Project WHERE Status = In Progress                                             |
| At Risk Projects      | At_Risk_Projects__c        | Number(18,0)            | DLRS: COUNT Project WHERE Health = Red AND Status NOT IN (Complete, Cancelled)             |
| Open Deliverables     | Open_Deliverables__c       | Number(18,0)            | DLRS: COUNT Deliverable WHERE Status NOT IN (Complete, Cancelled)                          |
| At Risk Deliverables  | At_Risk_Deliverables__c    | Number(18,0)            | DLRS: COUNT Deliverable WHERE Is_At_Risk__c = TRUE                                         |
| Open Cases            | Open_Cases__c              | Number(18,0)            | DLRS: COUNT Case WHERE IsClosed = FALSE                                                    |
| Deals Lost To         | Deals_Lost_To__c           | Number(18,0)            | DLRS: COUNT Opportunity WHERE Lost_To__c = this Account AND closed lost. For competitors   |
| Bookings Lost To      | Bookings_Lost_To__c        | Currency                | DLRS: SUM Opportunity.Amount, same filter                                                  |
| Executive Sponsor     | Executive_Sponsor__c       | Lookup(User)            | Optional                                                                                   |

#### Notes

- None of the rollups here can be native roll-up summaries. Native rollups need master-detail (plus a few standard pairs like Account → Opportunity), and every relationship feeding these is a lookup.

---

### 3.2 Contact

Contacts to Multiple Accounts (AccountContactRelation) is on. OWD Controlled by Parent.

#### Standard fields

| Field         | API Name     | Type            |
| ------------- | ------------ | --------------- |
| First Name    | FirstName    | Text            |
| Last Name     | LastName     | Text            |
| Account       | AccountId    | Lookup(Account) |
| Title         | Title        | Text            |
| Email         | Email        | Email           |
| Phone         | Phone        | Phone           |
| Mobile        | MobilePhone  | Phone           |
| Department    | Department   | Text            |
| Reports To    | ReportsToId  | Lookup(Contact) |
| Contact Owner | OwnerId      | Lookup(User)    |
| Description   | Description  | Long Text       |

#### Custom fields

| Field                    | API Name                    | Type                  | Values / Notes                                                                                                             |
| ------------------------ | --------------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Contact Role             | Contact_Role__c             | Multi-Select Picklist | Executive; Program Manager; Contracting Officer; Contracting Officer's Representative; Technical; Procurement; Supplier Manager; Support |
| Agency / Office          | Agency_Office__c            | Text(100)             | e.g., "PEO C3T", "DCMA Boston"                                                                                             |
| Preferred Contact Method | Preferred_Contact_Method__c | Picklist              | Email; Phone; Portal                                                                                                       |
| Portal Access            | Portal_Access__c            | Checkbox              | Display / request flag only. Actual access would come from enabling an Experience Cloud user                              |
| Primary Contact          | Primary_Contact__c          | Checkbox              | One per Account by convention (not enforced)                                                                               |
| Security Clearance       | Security_Clearance__c       | Picklist              | None; Secret; Top Secret; TS/SCI. Fictional demo data only                                                                 |

---

### 3.3 Opportunity

Internal OWD Read, external Private. Opportunity Teams are on. Field history is tracked on Amount, Close Date, Stage, Owner, Expected Contract Type, Estimated Contract Value, Estimated Margin, Capture Manager, Incumbent, Lost To, Loss Reason and Margin Approval Status.

#### Record types and sales processes

| Record type | Sales process | Stages | For |
| --- | --- | --- | --- |
| New Pursuit | New Pursuit | All 10 | New business and recompetes, with the full capture lifecycle |
| Contract Growth | Contract Growth | Identified; Proposal Development; Proposal Submitted; Discussions / Negotiation; Closed Won; Closed Lost; No Bid | Task orders, mods and option exercises on an existing contract (skips Qualified, Capture / Shaping, Bid Decision) |

Both have a Path.

#### Standard fields

| Field             | API Name         | Type            | Values / Notes                                                                 |
| ----------------- | ---------------- | --------------- | ------------------------------------------------------------------------------ |
| Opportunity Name  | Name             | Text            |                                                                                |
| Account           | AccountId        | Lookup(Account) |                                                                                |
| Amount            | Amount           | Currency        | **Base period value.** Total with options goes in Estimated Contract Value     |
| Close Date        | CloseDate        | Date            | Expected award date                                                            |
| Stage             | StageName        | Picklist        | See Stage table below                                                          |
| Probability       | Probability      | Percent         | Defaults from Stage                                                            |
| Forecast Category | ForecastCategory | Picklist        | Defaults from Stage                                                            |
| Opportunity Owner | OwnerId          | Lookup(User)    |                                                                                |
| Contract          | ContractId       | Lookup(Contract)| Set on growth deals; Flow #1 skips deals that already have one                 |
| Type              | Type             | Picklist        | New Business; Recompete; Task Order; Option Exercise; Contract Modification    |
| Lead Source       | LeadSource       | Picklist        | SAM.gov; RFI / Sources Sought; Agency Forecast; Industry Day; Partner Referral; Existing Customer |
| Next Step         | NextStep         | Text            |                                                                                |
| Description       | Description      | Long Text       |                                                                                |

#### Stage values

| Stage                     | Probability | Forecast Category | Closed / Won |
| ------------------------- | ----------- | ----------------- | ------------ |
| Identified                | 5%          | Pipeline          |              |
| Qualified                 | 10%         | Pipeline          |              |
| Capture / Shaping         | 20%         | Pipeline          |              |
| Bid Decision              | 30%         | Pipeline          |              |
| Proposal Development      | 40%         | Pipeline          |              |
| Proposal Submitted        | 50%         | Best Case         |              |
| Discussions / Negotiation | 75%         | Commit            |              |
| Closed Won                | 100%        | Closed            | Closed / Won |
| Closed Lost               | 0%          | Omitted           | Closed       |
| No Bid                    | 0%          | Omitted           | Closed       |

#### Custom fields

| Field                      | API Name                     | Type                | Values / Formula / Notes                                                                                      |
| -------------------------- | ---------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------- |
| Contract Vehicle           | Contract_Vehicle__c          | Picklist (GVS)      | Contract_Vehicle                                                                                              |
| Program Type               | Program_Type__c              | Picklist            | Research & Development; Prototype; Production; Sustainment; Professional Services; Training                   |
| Acquisition Type           | Acquisition_Type__c          | Picklist (GVS)      | Acquisition_Type                                                                                              |
| Prime / Subcontract        | Prime_Subcontract__c         | Picklist (GVS)      | Prime_Subcontract                                                                                             |
| Expected Contract Type     | Contract_Type__c             | Picklist (GVS)      | Contract_Type; copied to Contract on win                                                                      |
| Expected Contract Start    | Expected_Contract_Start__c   | Date                |                                                                                                               |
| Expected Contract End      | Expected_Contract_End__c     | Date                | Validation `Expected_End_After_Start`: `Expected_Contract_End__c < Expected_Contract_Start__c` → error       |
| Estimated Contract Value   | Estimated_Contract_Value__c  | Currency            | Total value incl. all options (ceiling / TCV)                                                                 |
| Incumbent                  | Incumbent__c                 | Lookup(Account)     | Lookup filter: `Account.Is_Competitor__c = TRUE`                                                              |
| Competitive                | Competitive__c               | Formula (Checkbox)  | `ISPICKVAL(Acquisition_Type__c, "Competitive")`                                                               |
| Capture Manager            | Capture_Manager__c           | Lookup(User)        |                                                                                                               |
| Program Manager            | Program_Manager__c           | Lookup(User)        | Carried to Contract on win                                                                                    |
| Customer Priority          | Customer_Priority__c         | Picklist (GVS)      | Priority                                                                                                      |
| Estimated Margin %         | Estimated_Margin__c          | Percent(5,2)        | Seeds Contract.Original_Margin__c on win                                                                      |
| Create Contract on Win     | Create_Contract_on_Win__c    | Checkbox            | Default TRUE. Flow #1 creates a Draft Contract on Closed Won when checked                                     |
| Loss Reason                | Loss_Reason__c               | Picklist            | Price; Technical; Past Performance; Incumbent Advantage; Schedule; No Bid; Other. Validation `Loss_Reason_Required`: required at Closed Lost |
| Lost To                    | Lost_To__c                   | Lookup(Account)     | Lookup filter: `Account.Is_Competitor__c = TRUE`. Feeds the competitor's Deals/Bookings Lost To              |
| Margin Floor %             | Margin_Floor__c              | Formula (Percent)   | `CASE(TEXT(Contract_Type__c), "Cost Plus", 0.07, "Time & Materials", 0.10, 0.12)`                             |
| Below Margin Floor         | Below_Margin_Floor__c        | Formula (Checkbox)  | `AND(NOT(ISBLANK(Estimated_Margin__c)), Estimated_Margin__c < Margin_Floor__c)`                               |
| Margin Shortfall           | Margin_Shortfall__c          | Formula (Currency)  | `IF(Below_Margin_Floor__c, Amount * (Margin_Floor__c - Estimated_Margin__c), NULL)`                           |
| Margin Approval Status     | Margin_Approval_Status__c    | Picklist            | Pending; Approved; Rejected. Set by the Margin Exception approval process; cleared by Margin Approval Reset   |
| Pricing Rationale          | Pricing_Rationale__c         | Long Text(5000)     | Drafted by Einstein (Opportunity_Pricing_Rationale) for the approver                                          |

#### Validation

- `Margin_Approval_Required`: `AND(Below_Margin_Floor__c, NOT(ISPICKVAL(Margin_Approval_Status__c, "Approved")), ISCHANGED(StageName), OR(IsWon, Probability >= 0.5))` blocks moving a below-floor deal into Proposal Submitted or later, or to Closed Won, without Pricing Review approval.

---

### 3.4 Contract

No record types. The design's **Government Award** record type wasn't built (see "If CPQ ever goes in this org"). Internal OWD Read/Write; field history tracked on the standard fields.

#### Standard fields

| Field               | API Name       | Type            | Notes                                                                                       |
| ------------------- | -------------- | --------------- | ------------------------------------------------------------------------------------------- |
| Contract Name       | Name           | Text            |                                                                                             |
| Contract Number     | ContractNumber | Auto Number     | Standard, read-only                                                                         |
| Account             | AccountId      | Lookup(Account) |                                                                                             |
| Contract Start Date | StartDate      | Date            |                                                                                             |
| Contract Term       | ContractTerm   | Number (months) | **Required for End Date.** Include option years if the record covers the full POP          |
| Contract End Date   | EndDate        | Date            | **Calculated** from Start Date + Term; not directly editable                                |
| Status              | Status         | Picklist        | Draft; In Approval Process; Activated (Expired and Terminated weren't added)                |
| Owner               | OwnerId        | Lookup(User)    |                                                                                             |
| Description         | Description    | Long Text       |                                                                                             |

#### Custom fields

| Field                   | API Name                   | Type                 | Values / Formula / Source                                                                             |
| ----------------------- | -------------------------- | -------------------- | ----------------------------------------------------------------------------------------------------- |
| Award Number            | Award_Number__c            | Text(50), Unique, External ID | e.g. DEN-2026-001. Named to avoid clashing with the standard Contract Number                 |
| Contract Type           | Contract_Type__c           | Picklist (GVS)       | Contract_Type                                                                                         |
| Acquisition Type        | Acquisition_Type__c        | Picklist (GVS)       | Acquisition_Type                                                                                      |
| Contract Vehicle        | Contract_Vehicle__c        | Picklist (GVS)       | Contract_Vehicle                                                                                      |
| Prime/Subcontract       | Prime_Subcontract__c       | Picklist (GVS)       | Prime_Subcontract                                                                                     |
| Contract Value          | Contract_Value__c          | Currency             | Total ceiling incl. options                                                                           |
| Funded Value            | Funded_Value__c            | Currency             | Obligated funding to date. Grows by the deal Amount when an Option Exercise deal is won                |
| Revenue Recognized      | Revenue_Recognized__c      | Currency             | DLRS: SUM Project__c.Revenue_Recognized__c                                                            |
| Actual Cost             | Actual_Cost__c             | Currency             | DLRS: SUM Project__c.Actual_Cost__c                                                                   |
| Revenue Allocation      | Revenue_Allocation__c      | Currency             | DLRS: SUM Project__c.Revenue_Allocation__c                                                            |
| Forecast Cost           | Forecast_Cost__c           | Currency             | DLRS: SUM Project__c.Forecast_Cost__c                                                                 |
| Unfunded Value          | Unfunded_Value__c          | Formula (Currency)   | `Contract_Value__c - Funded_Value__c`                                                                 |
| Funded Backlog          | Funded_Backlog__c          | Formula (Currency)   | `Funded_Value__c - Revenue_Recognized__c`                                                             |
| Total Backlog           | Total_Backlog__c           | Formula (Currency)   | `Contract_Value__c - Revenue_Recognized__c`                                                           |
| Percent Funded          | Percent_Funded__c          | Formula (Percent)    | `IF(Contract_Value__c > 0, Funded_Value__c / Contract_Value__c, 0)`                                   |
| Original Margin %       | Original_Margin__c         | Percent(5,2)         | Set once by Flow #1 from the Source Opportunity's Estimated Margin                                    |
| Current Margin %        | Current_Margin__c          | Formula (Percent)    | `IF(Revenue_Allocation__c > 0, (Revenue_Allocation__c - Forecast_Cost__c) / Revenue_Allocation__c, NULL)`. **Forecast margin at completion**, from project allocations and forecast costs (the design used Revenue Recognized and Actual Cost) |
| Margin Variance %       | Margin_Variance__c         | Formula (Percent)    | `Current_Margin__c - Original_Margin__c` (percentage points; negative = erosion)                     |
| Contract Health         | Contract_Health__c         | Picklist (GVS)       | Health_Status                                                                                         |
| Contracting Officer     | Contracting_Officer__c     | Lookup(Contact)      | Lookup filter: `Contact.AccountId = $Source.AccountId`                                                |
| COR                     | COR__c                     | Lookup(Contact)      | Contracting Officer's Representative, same filter                                                     |
| Program Manager         | Program_Manager__c         | Lookup(User)         | Receives Flow #12's option reminder                                                                   |
| Period of Performance   | Period_of_Performance__c   | Formula (Text)       | `TEXT(StartDate) & " - " & TEXT(EndDate)`                                                             |
| Current Period          | Current_Period__c          | Picklist             | Base; Option Year 1; Option Year 2; Option Year 3; Option Year 4. Moved up a year when an Option Exercise deal is won (Opportunity_Exercise_Option) |
| Next Option Date        | Next_Option_Date__c        | Date                 | Deadline to exercise the next option; Flow #12 reminds the PM 60 days prior. Moved a year later when an option is exercised |
| Security Requirement    | Security_Requirement__c    | Picklist             | None; CUI; Secret; Top Secret. Fictional demo data only                                               |
| Source Opportunity      | Source_Opportunity__c      | Lookup(Opportunity)  | Populated by Flow #1                                                                                  |

#### Validation

- `Original_Margin_Locked`: `AND(ISCHANGED(Original_Margin__c), ISPICKVAL(PRIORVALUE(Status), "Activated"))` → Original Margin % can't change once the contract is activated.

#### Notes

- One Contract record per award; option years are tracked with Current Period + Next Option Date rather than separate records. Growth (task orders, mods, option exercises) comes in through Contract Growth opportunities linked by `Opportunity.ContractId`; winning an Option Exercise deal updates the contract's period, option date and funding.

---

### 3.5 Project__c

Internal OWD Read/Write, external Private. Field history on.

#### Fields

| Field                  | API Name                  | Type                    | Values / Formula / Rollup                                                                                    |
| ---------------------- | ------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------ |
| Project Name           | Name                      | Text                    |                                                                                                              |
| Project Number         | Project_Number__c         | Auto Number             | PRJ-{0000}                                                                                                   |
| Contract               | Contract__c               | **Lookup(Contract)**, required, delete Restrict | Lookup, not M-D; see Architecture                                                   |
| Account                | Account__c                | Lookup(Account)         | Set by Flow #2 from Contract.AccountId                                                                       |
| Project Manager        | Project_Manager__c        | Lookup(User)            | Receives Deliverable Update notifications                                                                    |
| Status                 | Status__c                 | Picklist                | Planned; In Progress; On Hold; Complete; Cancelled. Default Planned                                          |
| Health                 | Health__c                 | Picklist (GVS)          | Health_Status                                                                                                |
| Start Date             | Start_Date__c             | Date                    |                                                                                                              |
| Target End Date        | Target_End_Date__c        | Date                    |                                                                                                              |
| Actual End Date        | Actual_End_Date__c        | Date                    | Validation `Actual_End_Required_When_Complete`                                                               |
| Percent Complete       | Percent_Complete__c       | Percent                 | PM's estimate                                                                                                |
| Deliverable Completion % | Deliverable_Completion__c | Formula (Percent)     | `IF(Deliverables__c > 0, Deliverables_Complete__c / Deliverables__c, 0)`, a system-calculated counterpart to the PM estimate |
| Budget                 | Budget__c                 | Currency                |                                                                                                              |
| Actual Cost            | Actual_Cost__c            | Currency                |                                                                                                              |
| Forecast Cost          | Forecast_Cost__c          | Currency                | Estimate at completion                                                                                       |
| Cost Variance          | Cost_Variance__c          | Formula (Currency)      | `Forecast_Cost__c - Budget__c` (positive = overrun)                                                          |
| Budget Variance %      | Budget_Variance__c        | Formula (Percent)       | `IF(Budget__c > 0, (Forecast_Cost__c - Budget__c) / Budget__c, NULL)`                                        |
| Revenue Allocation     | Revenue_Allocation__c     | Currency                | Share of Contract Value assigned to this project                                                             |
| Bid Margin %           | Bid_Margin__c             | Formula (Percent)       | `Contract__r.Original_Margin__c`                                                                             |
| Forecast Margin %      | Forecast_Margin__c        | Formula (Percent)       | `IF(Revenue_Allocation__c > 0, (Revenue_Allocation__c - Forecast_Cost__c) / Revenue_Allocation__c, NULL)`    |
| Margin Erosion %       | Margin_Erosion__c         | Formula (Percent)       | `Forecast_Margin__c - Bid_Margin__c` (NULL if either is blank; negative = erosion)                           |
| Subcontract Share %    | Subcontract_Share__c      | Formula (Percent)       | `IF(Budget__c > 0, Subcontracted_Value__c / Budget__c, NULL)`                                                |
| Revenue Recognized     | Revenue_Recognized__c     | Currency                | DLRS: SUM Deliverable__c.Revenue_Milestone__c WHERE Acceptance_Status__c = Accepted (revenue tied to acceptance) |
| Revenue at Risk        | Revenue_at_Risk__c        | Currency                | DLRS: SUM Deliverable__c.Revenue_Milestone__c WHERE Is_At_Risk__c = TRUE (summing the raw field with a filter avoids aggregating a formula field) |
| Subcontracted Value    | Subcontracted_Value__c    | Roll-up Summary (SUM)   | Supplier_Assignment__c.Contract_Value__c WHERE Status = Active                                               |
| Risk Level             | Risk_Level__c             | Picklist (GVS)          | Risk_Level. Manual                                                                                           |
| Open Risks             | Open_Risks__c             | Number(18,0)            | DLRS: COUNT Risk__c WHERE Status NOT IN (Closed, Realized)                                                   |
| Team Size              | Team_Size__c              | Roll-up Summary (COUNT) | Project_Resource__c WHERE Resource_Status__c = Active                                                        |
| Description            | Description__c            | Long Text               |                                                                                                              |
| Customer Sponsor       | Customer_Sponsor__c       | Lookup(Contact)         | Lookup filter: `Contact.AccountId = $Source.Account__c`                                                      |
| Internal Sponsor       | Internal_Sponsor__c       | Lookup(User)            |                                                                                                              |
| Deliverables           | Deliverables__c           | Number(18,0)            | DLRS: COUNT Deliverable__c (all)                                                                             |
| Deliverables Complete  | Deliverables_Complete__c  | Number(18,0)            | DLRS: COUNT Deliverable__c WHERE Status__c = Complete                                                        |
| Deliverables at Risk   | Deliverables_at_Risk__c   | Number(18,0)            | DLRS: COUNT Deliverable__c WHERE Is_At_Risk__c = TRUE                                                        |

#### Notes

- The draft's "Health = Red OR Status = At Risk" rollup can't be built directly because roll-up filters are AND-only. The OR logic lives in `Deliverable__c.Is_At_Risk__c`, and the rollup filters on that.
- Deliverable → Project is a **lookup** because of the supplier portal's sharing needs, so every deliverable-based rollup here runs through DLRS. Subcontracted Value and Team Size stay native roll-up summaries (those children are M-D).

---

### 3.6 Deliverable__c

Internal OWD Read/Write, external Private. Field history on. Change Data Capture is on for the live-updating components.

#### Fields

| Field                       | API Name                         | Type                     | Values / Formula / Notes                                                                                           |
| --------------------------- | -------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| Deliverable Name            | Name                             | Text                     | e.g., "CDRL A003 – System Security Plan"                                                                          |
| Deliverable Number          | Deliverable_Number__c            | Auto Number              | DEL-{00000}                                                                                                        |
| Project                     | Project__c                       | **Lookup(Project), required** | Lookup (not M-D) so a sharing set can grant suppliers access via Supplier__c. Delete **Restrict** (a Project with deliverables can't be deleted) |
| Contract                    | Contract__c                      | Lookup(Contract)         | Set by Flow #3 from Project                                                                                        |
| Account                     | Account__c                       | Lookup(Account)          | Set by Flow #3 from Project                                                                                        |
| Deliverable Type            | Deliverable_Type__c              | Picklist (GVS)           | Deliverable_Type                                                                                                   |
| Description                 | Description__c                   | Long Text                |                                                                                                                    |
| Owner                       | OwnerId                          | Lookup(User)             | Standard Owner (Deliverable isn't a detail object). Keep owners internal                                          |
| Status                      | Status__c                        | Picklist (GVS)           | Deliverable_Status: Not Started; In Progress; Blocked; Submitted; Complete; Cancelled                              |
| Health                      | Health__c                        | Picklist (GVS)           | Health_Status                                                                                                      |
| Priority                    | Priority__c                      | Picklist (GVS)           | Priority                                                                                                           |
| Percent Complete            | Percent_Complete__c              | Percent                  | Updated by Flow #6 from accepted supplier updates                                                                  |
| Planned Start Date          | Planned_Start_Date__c            | Date                     |                                                                                                                    |
| Due Date                    | Due_Date__c                      | Date                     | Contractual due date                                                                                               |
| Forecast Completion Date    | Forecast_Completion_Date__c      | Date                     |                                                                                                                    |
| Actual Completion Date      | Actual_Completion_Date__c        | Date                     | Validation `Actual_Completion_Required`: required when Status = Complete                                           |
| Schedule Variance (Days)    | Schedule_Variance_Days__c        | Formula (Number)         | `Forecast_Completion_Date__c - Due_Date__c` (positive = late)                                                      |
| Is Overdue                  | Is_Overdue__c                    | Formula (Checkbox)       | `AND(Due_Date__c < TODAY(), NOT(ISPICKVAL(Status__c, "Complete")), NOT(ISPICKVAL(Status__c, "Cancelled")))`. Reports only; TODAY() means it can't be used in a rollup |
| Acceptance Status           | Acceptance_Status__c             | Picklist (GVS)           | Acceptance_Status                                                                                                  |
| Acceptance Date             | Acceptance_Date__c               | Date                     | Stamped by Flow #3 the first time Acceptance Status → Accepted                                                     |
| Revenue Milestone           | Revenue_Milestone__c             | Currency                 | Amount billable on acceptance                                                                                      |
| Is At Risk                  | Is_At_Risk__c                    | Formula (Checkbox)       | `OR(ISPICKVAL(Health__c, "Red"), ISPICKVAL(Status__c, "Blocked"), ISPICKVAL(Risk_Level__c, "Critical"))`. No TODAY(), so it can feed rollups |
| Revenue at Risk             | Revenue_at_Risk__c               | Formula (Currency)       | `IF(Is_At_Risk__c, Revenue_Milestone__c, 0)`                                                                       |
| Supplier                    | Supplier__c                      | Lookup(Account)          | Lookup filter: `Account.Is_Supplier__c = TRUE`. Would drive portal access: the sharing set matches this field to the portal user's Account |
| Blocker Description         | Blocker_Description__c           | Long Text                | Validation `Blocker_Description_Required`: required when Status = Blocked                                          |
| Requires Customer Action    | Requires_Customer_Action__c      | Checkbox                 |                                                                                                                    |
| Customer Action Description | Customer_Action_Description__c   | Long Text                | Validation `Customer_Action_Description_Required`: required when Requires Customer Action = TRUE                   |
| Risk Level                  | Risk_Level__c                    | Picklist (GVS)           | Risk_Level                                                                                                         |
| Risk Description            | Risk_Description__c              | Long Text                | Quick summary; formal risks are Risk__c records                                                                   |
| Latest Update Date          | Latest_Update_Date__c            | Date/Time                | Stamped by Flow #6 when a supplier update is accepted                                                              |

#### Notes

- If a filter editor won't accept a multi-select picklist, the `Is_Supplier__c` formula checkbox on Account is the reason it exists. Filter on that instead.

---

### 3.7 Deliverable_Update__c

OWD Controlled by Parent. Field history on. Change Data Capture is on.

#### Fields

| Field                    | API Name                     | Type                         | Values / Notes                                                                        |
| ------------------------ | ---------------------------- | ---------------------------- | ------------------------------------------------------------------------------------- |
| Update Name              | Name                         | Auto Number                  | UPD-{00000}                                                                           |
| Deliverable              | Deliverable__c               | **Master-Detail(Deliverable)** | Sharing setting: **Read Only** (read on the Deliverable is enough to create updates) |
| Project                  | Project__c                   | Lookup(Project)              | Set by Flow #4 from Deliverable.Project__c                                            |
| Supplier                 | Supplier__c                  | Lookup(Account)              | Set by Flow #4 from Deliverable.Supplier__c if blank                                  |
| Submitted By             | Submitted_By__c              | Lookup(Contact)              | Flow #4: `$User.ContactId` for portal submissions                                     |
| Submitted Date           | Submitted_Date__c            | Date/Time                    | Default value `NOW()`                                                                 |
| Reported Status          | Reported_Status__c           | Picklist (GVS)               | Deliverable_Status. Named so it isn't confused with review status                     |
| Percent Complete         | Percent_Complete__c          | Percent                      |                                                                                       |
| Forecast Completion Date | Forecast_Completion_Date__c  | Date                         |                                                                                       |
| Progress Summary         | Progress_Summary__c          | Long Text                    | Required by validation rule `Progress_Summary_Required`                               |
| Blockers                 | Blockers__c                  | Long Text                    |                                                                                       |
| Next Steps               | Next_Steps__c                | Long Text                    |                                                                                       |
| Requires Customer Action | Requires_Customer_Action__c  | Checkbox                     |                                                                                       |
| Customer Action          | Customer_Action__c           | Long Text                    | Validation `Customer_Action_Required`: required when Requires Customer Action = TRUE  |
| Supplier Health          | Supplier_Health__c           | Picklist (GVS)               | Health_Status (supplier's self-assessment)                                            |
| Internal Review Status   | Internal_Review_Status__c    | Picklist                     | Pending; Under Review; Accepted; Needs Clarification; Rejected. Default Pending       |
| Reviewed By              | Reviewed_By__c               | Lookup(User)                 | Stamped by Flow #7                                                                    |
| Review Date              | Review_Date__c               | Date                         | Stamped by Flow #7                                                                    |
| Reviewer Comments        | Reviewer_Comments__c         | Long Text                    | Validation `Reviewer_Comments_Required`: required when Needs Clarification or Rejected |

Attachments go in the **Files** related list (not a field).

#### Workflow

**Supplier submits → Salesforce Flow → Project Manager notified → Update reviewed → Deliverable updated.** Internal users review in the Supplier Update Review component.

| Step | Flow | Detail |
| --- | --- | --- |
| Submit | #4 Update Intake (before create) | Fill blank Project, Supplier, Submitted By, Submitted Date |
| Notify | #5 Update Notify PM (after create, async) | Get Project → Project_Manager__c; send custom notification (bell + mobile) and email |
| Review | #7 Review Stamp (before update) | When Internal Review Status changes to Accepted / Needs Clarification / Rejected: Reviewed By = `$User.Id`, Review Date = `TODAY()` |
| Apply | #6 Update Review (after update, → Accepted) | Update parent Deliverable: Percent Complete, Forecast Completion Date, Status ← Reported Status, Requires Customer Action + description, blockers, Latest Update Date = NOW(). **Health stays PM-owned** and isn't overwritten by Supplier Health |
| Bounce | #6 async branch (→ Needs Clarification / Rejected) | Email submitter with Reviewer Comments |

#### Validation

- `Accepted_Update_Locked`: `AND(NOT(ISNEW()), ISPICKVAL(PRIORVALUE(Internal_Review_Status__c), "Accepted"))`, so an applied update can't be edited after the fact (Flow #6 updates the parent Deliverable, not this record, so it isn't blocked).
- `Supplier_Edit_Lock`: see Supplier portal. Inactive in practice until portal users exist, because it only fires for users with a ContactId.
- `Progress_Summary_Required`, `Customer_Action_Required`, `Reviewer_Comments_Required`: see the field table.

---

### 3.8 Supplier_Assignment__c

**Custom junction object**

Project ───< Supplier Assignment >─── Account

Project side is Master-Detail. Supplier side is a required Lookup (delete Restrict), so technically this isn't a strict junction (see Architecture), but related lists work in both directions.

#### Fields

| Field              | API Name                | Type                        | Values / Notes                                                                                                                                  |
| ------------------ | ----------------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Assignment Name    | Name                    | Auto Number                 | SA-{00000}                                                                                                                                      |
| Project            | Project__c              | **Master-Detail(Project)**  |                                                                                                                                                 |
| Supplier           | Supplier__c             | Lookup(Account), required   | Lookup filter: `Account.Is_Supplier__c = TRUE`                                                                                                  |
| Role               | Role__c                 | Picklist                    | Prime Contractor; Subcontractor; Hardware Supplier; Software Supplier; Engineering Partner; Logistics; Professional Services                    |
| Primary Supplier   | Primary_Supplier__c     | Checkbox                    | One per Project by convention (not enforced)                                                                                                    |
| Responsibility     | Responsibility__c       | Long Text                   | Statement of work summary                                                                                                                       |
| Start Date         | Start_Date__c           | Date                        |                                                                                                                                                 |
| End Date           | End_Date__c             | Date                        | Validation `End_After_Start`                                                                                                                    |
| Status             | Status__c               | Picklist                    | Proposed; Active; On Hold; Completed; Terminated. Default Proposed                                                                              |
| Supplier Manager   | Supplier_Manager__c     | Lookup(Contact)             | Lookup filter: `Contact.AccountId = $Source.Supplier__c`                                                                                        |
| Internal Owner     | Internal_Owner__c       | Lookup(User)                |                                                                                                                                                 |
| Contract Value     | Contract_Value__c       | Currency                    | Subcontract value; rolls up to Project.Subcontracted_Value__c (Active only)                                                                    |
| Performance Rating | Performance_Rating__c   | Picklist                    | Exceptional; Very Good; Satisfactory; Marginal; Unsatisfactory (CPARS scale, which reads authentically to gov audiences)                        |
| Notes              | Notes__c                | Long Text                   |                                                                                                                                                 |

---

### 3.9 Project_Resource__c

Junction object between Project__c and User

Project ───< Project Resource >─── User

Project is Master-Detail; User is a Lookup (User can't be a master).

#### Fields

| Field                 | API Name                | Type                       | Values / Notes                                                                                                                      |
| --------------------- | ----------------------- | -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Project Resource Name | Name                    | Auto Number                | RES-{00000}                                                                                                                         |
| Project               | Project__c              | **Master-Detail(Project)** |                                                                                                                                     |
| Employee              | Employee__c             | Lookup(User)               | Required by validation rule `Employee_Required` (the field itself is optional)                                                     |
| Role                  | Role__c                 | Picklist                   | Program Manager; Project Manager; Systems Engineer; Software Engineer; Cybersecurity Analyst; Test Engineer; Logistics Specialist; Trainer; Technical Writer |
| Start Date            | Start_Date__c           | Date                       |                                                                                                                                     |
| End Date              | End_Date__c             | Date                       | Validation `End_After_Start`                                                                                                        |
| Allocation %          | Allocation__c           | Percent                    | Validation `Allocation_Range`: between 0% and 100%                                                                                  |
| Billable              | Billable__c             | Checkbox                   | Default TRUE                                                                                                                        |
| Skill                 | Skill__c                | Text(255)                  | Fine for a demo; a picklist makes it reportable if you want skills analysis                                                        |
| Resource Status       | Resource_Status__c      | Picklist                   | Proposed; Assigned; Active; Rolled Off. Default Proposed                                                                            |
| Manager               | Manager__c              | Lookup(User)               | Set by Flow #14 from Employee's `ManagerId`                                                                                         |
| Unique Key            | Unique_Key__c           | Text(40), Unique           | Flow #14 sets Project Id + Employee Id, which blocks duplicate assignments of the same person to the same project                  |
| Notes                 | Notes__c                | Long Text                  |                                                                                                                                     |

This lets you answer:
> "Who is working on this project?" → related list on Project, plus Project.Team_Size__c rollup

and:
> "Where are our people allocated?" → report on Project Resources grouped by Employee, summing Allocation % (filter Resource Status = Active). Custom rollups onto User aren't available natively; a report is the simplest answer.

---

### 3.10 Service_Engagement__c

Internal OWD Read/Write, external Private. Field history on.

#### Fields

| Field                  | API Name                     | Type                 | Values / Formula / Notes                                                                                     |
| ---------------------- | ---------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------ |
| Service Name           | Name                         | Text                 |                                                                                                              |
| Service Number         | Service_Number__c            | Auto Number          | SVC-{00000}                                                                                                  |
| Contract               | Contract__c                  | Lookup(Contract)     |                                                                                                              |
| Account                | Account__c                   | Lookup(Account)      | Entered by hand / seed script. The design's before-save flow from Contract.AccountId **wasn't built**        |
| Service Type           | Service_Type__c              | Picklist (GVS)       | Service_Type                                                                                                 |
| Status                 | Status__c                    | Picklist             | Planned; Active; On Hold; Expired; Terminated. Default Planned                                               |
| Health                 | Health__c                    | Picklist (GVS)       | Health_Status                                                                                                |
| Service Owner          | Service_Owner__c             | Lookup(User)         |                                                                                                              |
| Start Date             | Start_Date__c                | Date                 |                                                                                                              |
| End Date               | End_Date__c                  | Date                 | Validation `End_After_Start`                                                                                 |
| Monthly Contract Value | Monthly_Contract_Value__c    | Currency             |                                                                                                              |
| Annual Contract Value  | Annual_Contract_Value__c     | Formula (Currency)   | `Monthly_Contract_Value__c * 12`                                                                             |
| Service Level          | Service_Level__c             | Picklist             | Platinum; Gold; Silver; Bronze. Descriptive tier only: one entitlement process serves every level (see below) |
| Entitlement            | Entitlement__c               | Lookup(Entitlement)  | Carries the actual SLA timers; Flow #8 stamps it onto Cases                                                  |
| Cases Open             | Cases_Open__c                | Number(18,0)         | DLRS: COUNT Case WHERE IsClosed = FALSE                                                                      |
| SLA Breaches           | SLA_Breaches__c              | Number(18,0)         | Cases with at least one violated milestone. Set hourly by the scheduled `SlaBreachRollup` job (see Rollup strategy) |
| Next Milestone Date    | Next_Milestone_Date__c       | Roll-up Summary (MIN) | Engagement_Milestone__c.Due_Date__c WHERE Status NOT IN (Complete, Cancelled)                               |
| Customer Satisfaction  | Customer_Satisfaction__c     | Number(2,1)          | 1.0–5.0 average CSAT. Manual for the demo                                                                    |
| Description            | Description__c               | Long Text            |                                                                                                              |
| Primary Contact        | Primary_Contact__c           | Lookup(Contact)      | Lookup filter: `Contact.AccountId = $Source.Account__c`                                                      |

#### Entitlement setup (as built)

- Entitlement Management is on (no entitlement versioning); milestone feed items are on.
- Milestone types: **First Response** and **Resolution** (plus the org's template types Close Case, Escalate Case and First Response to Customer, which aren't used).
- Entitlement process **Denali Service SLA** (24x7; no business hours). Starts from `Case.SlaStartDate` (set by Flow #16) and exits when the case closes. Milestone times by Case Priority:

  | Priority | First Response | Resolution |
  | --- | --- | --- |
  | Critical | 1 hour | 1 day |
  | High | 4 hours | 3 days |
  | Medium | 8 hours | 5 days |
  | Low | 24 hours | 10 days |

- The clock stops while a case is **Waiting on Customer** (Flow #16 sets `IsStopped`). Waiting on Supplier keeps it running.
- Milestones are completed by Flow #15, not by hand. The processes have **no milestone actions** (no 75% warning, no violation escalation). That's still to build if you want it.
- A second process, **Denali Government Support**, has the same milestones but starts from `Case.CreatedDate`. No entitlement uses it.
- Entitlements on Denali processes: *FLC Network Operations Support SLA* (Federal Logistics Command) and *NDA Sensor Sustainment SLA* (Northwind Defense Agency), both on Denali Service SLA. The template's *Sample Entitlement* uses Standard Case.
- The design's "one entitlement process per Service Level" wasn't built. To make Service Level change SLA times, add a process per level and point each engagement's Entitlement at the matching one.

---

### 3.11 Engagement_Milestone__c

*Built as `Engagement_Milestone__c` (the draft's `Service_Milestone__c`) so it doesn't collide with Service Cloud's standard Milestone objects.* OWD Controlled by Parent. Field history on.

#### Fields

| Field               | API Name                  | Type                         | Values / Notes                                                                                                                         |
| ------------------- | ------------------------- | ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Milestone Name      | Name                      | Text                         |                                                                                                                                        |
| Service Engagement  | Service_Engagement__c     | **Master-Detail(Service_Engagement__c)** |                                                                                                                  |
| Contract            | Contract__c               | Lookup(Contract)             | Entered by hand / seed script (the defaults flow wasn't built). Flow #13 reads it                                                     |
| Account             | Account__c                | Lookup(Account)              | Entered by hand / seed script (the defaults flow wasn't built)                                                                        |
| Milestone Type      | Milestone_Type__c         | Picklist                     | Monthly Review; Maintenance; Release; Certification; Readiness Assessment; SLA Review; Training; Renewal                               |
| Status              | Status__c                 | Picklist                     | Not Started; Scheduled; In Progress; Complete; Missed; Cancelled. Default Not Started                                                  |
| Health              | Health__c                 | Picklist (GVS)               | Health_Status                                                                                                                          |
| Owner               | Milestone_Owner__c        | Lookup(User)                 | Custom lookup; M-D detail records have no standard Owner                                                                               |
| Planned Date        | Planned_Date__c           | Date                         | Originally scheduled date (baseline)                                                                                                   |
| Due Date            | Due_Date__c               | Date                         | Current committed date                                                                                                                 |
| Completion Date     | Completion_Date__c        | Date                         | Validation `Completion_Date_Required`: required when Status = Complete                                                                 |
| Slip (Days)         | Slip_Days__c              | Formula (Number)             | `Due_Date__c - Planned_Date__c`                                                                                                        |
| Is Overdue          | Is_Overdue__c             | Formula (Checkbox)           | `AND(Due_Date__c < TODAY(), NOT(ISPICKVAL(Status__c, "Complete")), NOT(ISPICKVAL(Status__c, "Cancelled")))`                            |
| Percent Complete    | Percent_Complete__c       | Percent                      |                                                                                                                                        |
| Customer Acceptance | Customer_Acceptance__c    | Picklist (GVS)               | Acceptance_Status                                                                                                                      |
| Revenue Impact      | Revenue_Impact__c         | Currency                     | Award fee, incentive, or renewal value tied to this milestone                                                                          |
| Description         | Description__c            | Long Text                    |                                                                                                                                        |
| Notes               | Notes__c                  | Long Text                    |                                                                                                                                        |

#### Automation

- **Flow #13:** Milestone Type = Renewal → 90 days before Due Date creates an Opportunity (Option Exercise or Recompete, Account/Contract prefilled, Amount = Service Engagement ACV). This ties service delivery back to the revenue lifecycle.

---

### 3.12 Case

Internal OWD Read/Write/Transfer, external Private. Field history on Status, Priority, Owner, Type, Reason, Origin, Subject, Description, Contact, Asset. Case Feed and Email-to-Case are on; Web-to-Case is off. The Case **Service Lifecycle** path is in place. **Lightning Knowledge** is on, with a custom `Knowledge__kav.Details__c` rich-text field.

#### Standard fields

| Field         | API Name       | Values / Notes                                                                                                              |
| ------------- | -------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Case Number   | CaseNumber     |                                                                                                                             |
| Contact       | ContactId      |                                                                                                                             |
| Account       | AccountId      |                                                                                                                             |
| Status        | Status         | New; Working; Waiting on Customer; Waiting on Supplier; Resolved; Closed. Only Waiting on Customer stops the SLA clock (Flow #16) |
| Priority      | Priority       | Low; Medium; High; Critical. Standard picklist can't bind to the Priority GVS; values match manually. Drives milestone times |
| Origin        | Origin         | Email; Phone; Portal; Web                                                                                                   |
| Case Owner    | OwnerId        |                                                                                                                             |
| Subject       | Subject        |                                                                                                                             |
| Description   | Description    |                                                                                                                             |
| Type          | Type           | Incident; Service Request; Problem; Change Request; Question                                                               |
| Reason        | Reason         | Outage; Degraded Performance; Security Event; Hardware Failure (Incident) · Access Request; Configuration Change; Training Request; Equipment Request (Service Request) · Recurring Incident; Known Error (Problem) · Standard Change; Emergency Change (Change Request). The grouping is by convention: Reason **isn't a dependent picklist** on Type |
| Escalated     | IsEscalated    | Standard checkbox, replacing the custom "Escalated" field                                                                   |
| Entitlement   | EntitlementId  | Set by Flow #8 from Service_Engagement__r.Entitlement__c                                                                   |
| Milestone Status | MilestoneStatus | Standard: Compliant / Open Violation / Closed Violation. Replaces custom "SLA Status"                                  |
| SLA Start / Exit / Stopped | SlaStartDate, SlaExitDate, IsStopped | Standard entitlement fields; Flow #16 sets SlaStartDate and IsStopped. The Case Milestones related list shows target dates, replacing custom "SLA Target" |
| Created Date  | CreatedDate    |                                                                                                                             |
| Closed Date   | ClosedDate     |                                                                                                                             |

#### Custom fields

| Field              | API Name                | Type                | Values / Notes                                                                                                  |
| ------------------ | ----------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------- |
| Service Engagement | Service_Engagement__c   | Lookup(Service_Engagement__c) | Lookup filter: `Service_Engagement__c.Account__c = $Source.AccountId`                                 |
| Project            | Project__c              | Lookup(Project__c)  | Lookup filter: `Project__c.Account__c = $Source.AccountId`                                                      |
| Deliverable        | Deliverable__c          | Lookup(Deliverable__c) | Lookup filter: `Deliverable__c.Project__c = $Source.Project__c`                                              |
| Service Type       | Service_Type__c         | Formula (Text)      | `TEXT(Service_Engagement__r.Service_Type__c)`. Replaces "Case Category", which duplicated Type/Reason          |
| Severity           | Severity__c             | Picklist            | Sev 1 - Critical Outage; Sev 2 - Major Degradation; Sev 3 - Minor Issue; Sev 4 - Informational / Request        |
| Customer Impact    | Customer_Impact__c      | Picklist            | Single User; Multiple Users; Site / Program; Enterprise / Mission. Scope of impact, distinct from Severity      |
| Escalation Reason  | Escalation_Reason__c    | Picklist            | SLA Risk; Customer Request; Executive Visibility; Technical Complexity; Supplier Dependency. Validation `Escalation_Reason_Required`: required when IsEscalated = TRUE |
| Escalation Notes   | Escalation_Notes__c     | Long Text           | Free-text context                                                                                               |
| Root Cause         | Root_Cause__c           | Picklist            | Configuration; Software Defect; Hardware Failure; Network / Infrastructure; User Error; Supplier Issue; Documentation Gap; Process Gap; Unknown |
| Resolution Summary | Resolution_Summary__c   | Long Text           | Validation `Resolution_Summary_Required`: required when Status = Closed                                         |
| SLA Breached       | SLA_Breached__c         | Checkbox            | `optional/`. Checked when any of the case's SLA milestones is violated; set hourly by `SlaBreachRollup`. Read-only for users. Case list view **SLA Breached** filters on it |

#### Validation

- `Root_Cause_Required_On_Close`: Root Cause required on close when Type = Incident or Problem.

#### Priority matrix (Flow #9)

| Severity ↓ / Impact → | Single User | Multiple Users | Site / Program | Enterprise / Mission |
| --- | --- | --- | --- | --- |
| Sev 1 | High | Critical | Critical | Critical |
| Sev 2 | Medium | High | High | Critical |
| Sev 3 | Low | Medium | Medium | High |
| Sev 4 | Low | Low | Low | Medium |

Priority then drives the entitlement milestone times, which is a strong Service Cloud demo moment.

#### Automation

- **Flow #8:** EntitlementId ← Service Engagement's Entitlement.
- **Flow #9:** Priority from the Severity × Customer Impact matrix above.
- **Flow #10:** Sev 1/2 Case with a Deliverable → creates an Identified, Technical Risk__c on that Deliverable, with Revenue at Risk, Risk Owner, Target Resolution Date and Consequence filled in; Likelihood is left for the PM.
- **Flow #15:** completes First Response when the case leaves New, and all open milestones on close.
- **Flow #16:** starts the SLA clock on new cases; stops it while Waiting on Customer.

Customer
   ↓
Contract
   ↓
Service
   ↓
Case
   ↓
Potential Deliverable / Project impact (via Flow #10 → Risk__c)

---

### 3.13 Risk__c

Internal OWD Read/Write, external Private. Field history on.

#### Fields

| Field                  | API Name                      | Type                  | Values / Formula / Notes                                                                                                      |
| ---------------------- | ----------------------------- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Risk Name              | Name                          | Text                  |                                                                                                                               |
| Risk Number            | Risk_Number__c                | Auto Number           | RSK-{00000}                                                                                                                   |
| Account                | Account__c                    | Lookup(Account)       | Filled upward by Flow #11                                                                                                     |
| Contract               | Contract__c                   | Lookup(Contract)      | Filled upward by Flow #11                                                                                                     |
| Project                | Project__c                    | Lookup(Project__c)    | Filled upward by Flow #11                                                                                                     |
| Deliverable            | Deliverable__c                | Lookup(Deliverable__c)|                                                                                                                               |
| Risk Category          | Risk_Category__c              | Picklist (GVS)        | Risk_Category                                                                                                                 |
| Likelihood             | Likelihood__c                 | Picklist              | 1 - Not Likely; 2 - Low Likelihood; 3 - Likely; 4 - Highly Likely; 5 - Near Certainty. Named to avoid confusion with Opportunity.Probability |
| Consequence            | Consequence__c                | Picklist              | 1 - Minimal; 2 - Minor; 3 - Moderate; 4 - Significant; 5 - Severe (5×5 matrix, DoD risk-management style)                     |
| Risk Score             | Risk_Score__c                 | Formula (Number)      | `VALUE(LEFT(TEXT(Likelihood__c), 1)) * VALUE(LEFT(TEXT(Consequence__c), 1))` (1–25)                                           |
| Severity               | Severity__c                   | Formula (Text)        | Blank until both Likelihood and Consequence are set; then `IF(Risk_Score__c >= 15, "Critical", IF(Risk_Score__c >= 10, "High", IF(Risk_Score__c >= 5, "Medium", "Low")))`, same labels as Risk_Level |
| Status                 | Status__c                     | Picklist              | Identified; Analyzing; Mitigating; Monitoring; Realized; Closed. Default Identified ("Realized" = the risk became an issue)   |
| Owner                  | Risk_Owner__c                 | Lookup(User)          | Risk also has the standard OwnerId (it isn't a detail object)                                                                 |
| Identified Date        | Identified_Date__c            | Date                  | Default `TODAY()`                                                                                                             |
| Target Resolution Date | Target_Resolution_Date__c     | Date                  |                                                                                                                               |
| Closed Date            | Closed_Date__c                | Date                  | Manual. The design's stamp on Closed / Realized **wasn't built**                                                              |
| Mitigation Plan        | Mitigation_Plan__c            | Long Text             | Validation `Mitigation_Plan_Required`: required when Severity = High or Critical                                              |
| Contingency Plan       | Contingency_Plan__c           | Long Text             |                                                                                                                               |
| Revenue at Risk        | Revenue_at_Risk__c            | Currency              |                                                                                                                               |
| Cost Impact            | Cost_Impact__c                | Currency              |                                                                                                                               |
| Financial Impact       | Financial_Impact__c           | Formula (Currency)    | `BLANKVALUE(Revenue_at_Risk__c, 0) + BLANKVALUE(Cost_Impact__c, 0)`                                                           |

#### Validation

- `At_Least_One_Parent`: `AND(ISBLANK(Account__c), ISBLANK(Contract__c), ISBLANK(Project__c), ISBLANK(Deliverable__c))` → error.

#### Automation

- **Flow #11 (before save):** Deliverable set → fill Project, Contract, Account from it. Project set → fill Contract, Account. Contract set → fill Account.
- Feeds Project.Open_Risks__c (DLRS).

---

### 3.14 Asset / Product2

Added after the original design so customer Accounts show their installed base.

| Object | Field | API Name | Type | Notes |
| --- | --- | --- | --- | --- |
| Product2 | Track as Asset | Track_as_Asset__c | Checkbox | Checked for hardware, licenses and annual services; labor, implementation and training stay unchecked |
| Asset | Source Opportunity | Source_Opportunity__c | Lookup(Opportunity) | The won deal that created the asset |

**Opportunity_Create_Assets_on_Win** (Closed Won) calls `OpportunityAssets` Apex to create one Asset per Opportunity Product whose Product has Track as Asset checked. The seed scripts add a product catalog and a GSA Schedule price book.
