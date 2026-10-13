# Denali Defense Demo Org Kit

This kit rebuilds the Denali Defense demo in a Salesforce org. It includes:
- **Data model:** the government-contracting data model (see `Demo_Org_Data_Model.md`).
- **Automation:** the flow inventory, plus a margin approval process.
- **Analytics and apps:** revenue and margin dashboards, Lightning Web Components, and two persona apps (General Manager and Project Manager).
- **Demo data:** a connected set of records that tells the story.

The demo answers five discovery themes:

| Theme | Where the demo answers it |
| --- | --- |
| Missed revenue targets | Revenue Health dashboard (bookings against target, revenue at risk, backlog, option dates) |
| Sliding margins and competition | Margin floors, Margin Exception approval, Margin Guardrail, Competitor Intel, Margin & Competition dashboard |
| Visibility across customer, supplier and employee lifecycles | Account Command Center, role-aware Account pages, Project timeline |
| Mobility and channels | Supplier Update Review and approvals in the Salesforce mobile app |
| Collaboration and information sharing | Supplier update review loop, custom notifications, live-updating components, Pricing Approvals |

## What's in the kit

| Folder | Contents | Deploy |
| --- | --- | --- |
| `force-app/` | Everything core: data model, automation, analytics, Apex, components, Lightning pages, permission set | 1st. Needs **Sales Account Plans** on (the Denali Account page lists them) |
| `optional/` | Entitlement lookup, government standard picklist values (including the capture-lifecycle Opportunity stages, product families and units of measure), the two Opportunity sales processes with their record types and paths, and the Service Cloud pieces: the **Denali Service SLA** entitlement process and its milestone types, the Case Service Lifecycle path, the Knowledge Details field, four Case flows, the hourly SLA Breaches rollup (`SlaBreachRollup`) with the Case **SLA Breached** flag and list view, and quarterly Forecasts with quotas shown (forecast settings) | After `force-app`, **only in a clean demo org** (see notes) |
| `ai/` | Opportunity Pricing Rationale flow (Einstein) | After the prompt template is active |
| `dlrs/` | 21 Realtime lookup rollups (Declarative Lookup Rollup Summaries), their 6 child triggers, and a test | After `force-app`. **Needs the DLRS package installed** |
| `agentforce/` | **Denali Assistant**, an Agentforce employee agent (Agent Script), and the Apex actions behind it | After `force-app`. **Needs Agentforce** |
| `account-plans/` | The Open Pipeline calculation for Sales Account Plan measures | After enabling **Sales Account Plans**. Then activate it (see below) |
| `persona-apps/` | **Denali Portfolio** and **Denali Delivery** apps (desktop) with their phone-only **Mobile** apps, the **Denali Persona Apps** permission set, and the role hierarchy under CEO | After `force-app` |
| `standard-layouts/` | Opportunity, Contract, Case and Contact page layouts | Last, and deliberately: **replaces the org's layouts** |
| `scripts/apex/` | Verify and grant access, seed demo data, recalculate rollups, schedule the SLA Breaches rollup, reset | After the deploys |
| `workbench/` | The five metadata folders as zips, for deploying without the CLI | Option B below |

## What it builds

### Data model (`force-app`)
- **12 global value sets.**
- **8 custom objects**, each with a tab and a page layout: Project, Deliverable, Deliverable Update, Supplier Assignment, Project Resource, Service Engagement, Engagement Milestone, Risk.
- **Custom fields** on Account, Contact, Opportunity, Contract and Case, including margin and competition fields:
  - Opportunity: Margin Floor, Below Margin Floor, Margin Shortfall, Margin Approval Status, Pricing Rationale, Loss Reason, Lost To.
  - Project: Bid, Forecast and Erosion margin, Subcontract Share.
  - Contract: Revenue Allocation, Forecast Cost.
  - Asset: Source Opportunity (the won deal it came from).
  - Product: Track as Asset (which product lines become installed-base assets on a win).
  - Account: Deals and Bookings Lost To.
- **24 validation rules**, including:
  - The supplier edit lock and the accepted-update lock.
  - The margin approval gate.
  - Loss Reason required at Closed Lost.
- **Lookup filters:** supplier-only, competitor-only, same-account contacts, and a Case's Deliverable must belong to its Project.
- **Opportunity field history:** 13 fields are tracked, for the audit trail and Slack record alerts:
  - Standard: Stage, Amount, Close Date, Owner, Forecast Category.
  - Margin: Estimated Margin, Contract Type, Margin Approval Status, Estimated Contract Value.
  - Competition: Incumbent, Lost To, Loss Reason, Capture Manager.
  - The margin formulas (Below Margin Floor, Margin Floor, Margin Shortfall) can't be tracked, so their inputs are tracked instead. Opportunity allows 20 tracked fields, which leaves 7.
- **Native roll-up summaries:** Subcontracted Value, Team Size, Next Milestone Date.
- **Change Data Capture** on Deliverable and Deliverable Update, which drives the live-updating components. It uses 2 of the org's CDC object selections.
- **Account list views:** Denali Customers, Denali Suppliers, Denali Competitors.

### Automation
- **The 16 inventory flows:**
  - 12 in `force-app`: Create Contract on Win, Project, Deliverable and Resource defaults, Update Intake, Notify PM, Review and Review Stamp, Case → Risk, Risk Parents, Option Reminder, Renewal Opp.
  - Create Contract on Win skips deals already linked to a Contract (task orders, mods, option exercises), so closing them doesn't duplicate the contract.
  - 4 in `optional/`: Case Entitlement, Case Priority Matrix, Case Complete Milestones (First Response when a case leaves New; every open milestone when it closes) and Case SLA Clock (starts a new case's SLA clock, and stops it while Waiting on Customer).
- **Margin Exception approval process:** opportunities below their floor need approval before reaching a proposal stage or Closed Won.
  - **Floors by contract type:** Cost Plus 7%, T&M 10%, Fixed Price 12%.
  - **Approver:** the submitter chooses it, because Salesforce doesn't allow a queue to approve Opportunities.
  - **Opportunity Margin Approval Reset** flow: clears an approval if the margin or contract type changes afterwards.
- **Opportunity Pricing Rationale** (`ai/`): when a deal drops below its floor, the **Pricing Rationale** prompt template drafts a justification for the approver.
- **Custom notification type** "Deliverable Update Submitted", used by Notify PM.
- **SLA Breaches** (`optional/`): the scheduled `SlaBreachRollup` class checks **SLA Breached** on each case with a violated SLA milestone (and clears it when none is left), then counts those cases into each Service Engagement's SLA Breaches, hourly. The Case list view **SLA Breached** and case reports filter on the flag. It's scheduled rather than a realtime rollup because milestones violate as time passes, not when a record is saved. `10_schedule_sla_breach_rollup.apex` schedules it.
- **Closed Won → installed base** (`force-app`): the **Opportunity Create Assets on Win** flow calls `OpportunityAssets`, which creates an Asset for each assetizable product line on the won deal. Only the installed base is assetizable: hardware, the software license and the annual services (labor, implementations and training aren't). Annual services get a Usage End Date from the close date and the number of years, so renewals and option decisions show.
- **Option exercise grows the contract** (`force-app`): when an Option Exercise deal linked to a Contract closes as won, the **Opportunity Exercise Option** flow moves the Contract's Current Period up a year, moves Next Option Date a year later (clearing it after the last option year or at the contract end), and adds the deal Amount to Funded Value. Contract Value is the ceiling and already includes the options, so it only rises if the new funding would exceed it. Option Reminder then reschedules for the new option date.
- **Account plans stay current** (`account-plans/`): Salesforce only calculates an account plan measure when a deal is linked to it. The **Opportunity Refresh Account Plan Measures** flow re-saves a deal's links whenever its stage or amount changes (`AccountPlanMeasureRefresh`), so closing a deal moves its plan straight away.

### Analytics (`force-app`)
- **Report types:** 3 custom ones (Deliverable Revenue, Contract Backlog, Project Margin).
- **Reports:** 15, in two folders.
- **Revenue Health dashboard:**
  - Last quarter's bookings against a static **$5.5M** target, and the fiscal year's against **$22M** ($5.5M a quarter); both gauges are red under 80% of target.
  - Open pipeline and bookings by quarter.
  - Revenue milestones by acceptance, and revenue at risk.
  - Contract backlog, and option decisions due in 90 days.
- **Margin & Competition dashboard:**
  - Average forecast margin, and win rate (won ÷ closed, not counting No Bid).
  - Pipeline below floor.
  - Bookings lost to competitors, with losses by competitor and reason.
  - Margin erosion by project, contract margin variance.
  - Won margin and win rate by acquisition type.

### Forecasts (`optional/` and `11`)
- **Quarterly forecasts** on the Opportunity Amount forecast type, showing last quarter and the next three, with quotas shown (`optional/main/default/settings/Forecasting.settings-meta.xml`).
- **Quotas:** `11_seed_forecast_quotas.apex` gives each forecast-enabled General Manager a **$5.5M** quota for each of those quarters, so the Revenue Health target is a real quota. Last quarter shows $3.7M closed against it (67%).
- **Forecast manager:** `01_verify_and_grant_access.apex` makes the General Manager the forecast manager of their role (Setup → Forecasts Hierarchy). Roles are setup records, which can't change in the same transaction as quotas.
- **Forecasts tab** in Denali Portfolio, after Opportunities. Use the **Grid** view: the Chart view's Quarterly Trends compare against forecast snapshots, which Salesforce only records as time passes, so they read $0 on freshly seeded data.
- **This quarter:** FLC Option Year 2 closes two weeks before its option date, so it's this quarter's $1.85M Best Case, and closing it in the demo moves it to Closed.
- The Revenue Health gauge keeps its fixed $5.5M: a dashboard gauge can't read a quota.

### Rollups (`dlrs/`)
The lookup rollups are 21 **Declarative Lookup Rollup Summaries (DLRS)** definitions, stored as `dlrs__LookupRollupSummary2__mdt` custom metadata, all in **Realtime** mode with **System** sharing.

| Parent | Rollups | From |
| --- | --- | --- |
| Project | Deliverables, Complete, At Risk, Revenue Recognized, Revenue at Risk | Deliverables |
| Project | Open Risks | Risks |
| Contract | Revenue Recognized, Actual Cost, Revenue Allocation, Forecast Cost | Projects |
| Account | Total and Active Contract Value, Contract Backlog | Contracts |
| Account | Active Projects, At-Risk Projects | Projects |
| Account | Open Deliverables, At-Risk Deliverables | Deliverables |
| Account | Open Cases | Cases |
| Account (competitor) | Deals Lost To, Bookings Lost To | Opportunities (Lost To) |
| Service Engagement | Cases Open | Cases |

- **Triggers:** Realtime mode needs a DLRS child trigger on Deliverable, Risk, Project, Contract, Case and Opportunity. They're the one-line handler DLRS generates, named so DLRS's *Manage Child Trigger* screen recognises them.
- **Chaining:** rollups chain in the same save. A deliverable change updates its Project, which updates its Contract, which updates its Account.
- **Test:** `DlrsRollupsTest` checks the whole chain with real records and covers the triggers 100%. DLRS's generated test stubs insert blank records, which this org's required fields and validation rules reject.
- **SLA Breaches** isn't a DLRS rollup: it comes from the hourly `SlaBreachRollup` job in `optional/` (see Automation).

### Lightning Web Components and Apex (`force-app`)

| Component | Where | What it shows |
| --- | --- | --- |
| **Account Command Center** | Account page (Command Center tab), and Denali Portfolio's **Account Command Center** tab, an app page with a drop-down of active customers labelled with their award numbers ("Northwind Defense Agency - NDA-2026-001") | KPIs, contract cards (funding, margin, option countdown), contract → project → deliverable tree, delivery timeline, risk heat map, service. Health shows as SLDS success, warning and error icons; SLA breaches and the margin floor use the SLDS score icon |
| **Account Command Center (Mobile)** | Denali Portfolio Mobile's **Command Center** tab | The same data laid out for phones: the active-customer drop-down, KPIs two to a row, then collapsible sections for what needs attention (at-risk and overdue deliverables), contracts (funding bar, margin, option countdown), projects, top risks, and service and cases. Rows open their records. No tree grid, timeline or heat map, and no live updates (the mobile app has no streaming), so it has a Refresh button |
| **Account Supplier Updates** | Account page sidebar | Supplier updates on the account's deliverables waiting on internal review |
| **Account Suppliers** | Account page sidebar | Suppliers assigned to the account's projects, with role, rating and value |
| **Account Team** | Account page sidebar | Who's working on the account's projects, with role and allocation |
| **Margin Guardrail** | Opportunity page | Margin against the floor and against recent wins, profit given up, approval status with inline submit, Pricing Rationale with **Regenerate with Einstein** |
| **Competitor Intel** | Opportunity page (the incumbent); competitor Account page | Win rate, bookings won and lost, margin on wins against losses, loss reasons, recent head-to-head deals. A summary compares the average margin on wins and losses and, on an open opportunity, the deal's margin against its floor |
| **Contract Health** | Contract page | Funding bar, margin at award against forecast, option countdown, what's at risk underneath |
| **Pricing Approvals** | Portfolio Home | Margin Exception approval requests waiting on you, with pricing facts, rationale, and approve/reject. Other approvals stay in the standard Items to Approve list |
| **Project Timeline** | Project page | Deliverables as a timeline, with slips to forecast dates and a today line |
| **My Projects** | Delivery Home | My projects' health, updates to review, due in 30 days, open risks |
| **Supplier Update Review** | Deliverable page (desktop and mobile) | Supplier updates with a % complete trend; Accept / Needs Clarification / Reject inline |
| **Impact Chain** | Case page | Case → Service → Deliverable → Project → Contract, the revenue at stake, open risks. A support case with no Deliverable or Project follows its Service Engagement to the Contract (service value, days to the option decision, the contract's open risks) |

- **Apex:** nine controllers plus six test classes. Queries run in user mode, so sharing and field-level security apply. The three Account sidebar components use their own methods on the Command Center controller.
- **Account sidebar components:** they read the account from the record page, so they work on Account record pages only, not on the Command Center app page.
- **Health and score icons:** `healthDot` shows Green/Yellow/Red as the SLDS `utility:success`, `utility:warning` and `utility:error` icons in their semantic colours, so the shape carries the meaning as well as the colour. `healthDatatable` is a `lightning-datatable` with a `health` column type that uses it, and a `score` column type that puts the SLDS score dynamic icon (`lightning-dynamic-icon type="score"`) before a value: the Service table's SLA Breaches column. Margin Guardrail uses the same score icon for above or below the floor. The Command Center's tree grid can't use custom column types, so it shows 🟢🟡🔴 instead.
- **Live updates:** My Projects, the Command Center, Account Supplier Updates, Project Timeline and Supplier Update Review subscribe to the Change Data Capture events and refresh when deliverables or updates change. This works on desktop only, because the mobile app has no streaming. The live components show **● Live** when subscribed.

### Denali Assistant (`agentforce/`)
An Agentforce **employee agent**, so it runs as the person asking: their sharing and field access apply, and "my approvals" are simply theirs. It's written in Agent Script (`aiAuthoringBundles/Denali_Assistant`), and its actions are Apex classes that reuse the components' controllers, so the agent and the Lightning pages show the same numbers.

| Topic | Actions | Built on |
| --- | --- | --- |
| Program Briefing | Get Program Briefing (one contract's funded backlog, margin variance, at-risk deliverables, open risks, open cases with their SLA status, and next option date; finds it by award number, contract number, project or account) | Contract, Project, Deliverable, Risk and Case records |
| Portfolio Risk | Get Portfolio Risk (every account rated at risk, watch or clear, with reasons and out-of-date health ratings); Get Account Overview | Account Command Center controller |
| Pricing Approvals | Get My Pricing Approvals; Decide Pricing Approval (confirms with the user first) | Pricing Approvals controller |
| Delivery Status | Get My Projects (the user's active projects, what's due in 30 days, updates to review); Get Deliverable Status (supplier updates, % complete trend, stalled progress) | My Projects and Supplier Update Review controllers |
| Service Status | Get Case Briefing (one case by number or subject: severity, SLA milestones breached or time left, what it puts at risk, linked risks, attached articles); Get Open Cases (open cases across accounts or for one, most urgent first, with SLA breaches, escalations and the revenue at stake) | Impact Chain controller, Case and SLA milestone records. SLA and article details need Entitlement Management and Knowledge; without them those parts are left out |

- **Publishing:** `scripts/publish_agent.sh`. Each publish creates a new, **inactive** agent version, so activate it afterwards (`sf agent activate --api-name Denali_Assistant --version <n>`) or Slack and Lightning keep using the old one; the bot and planner metadata it retrieves into `agentforce/` is git-ignored, because it carries org-specific IDs.
- **After publishing:** activate the agent, deploy the **Denali Assistant Access** permission set (`agentforce/.../permissionsets`) and assign it with Demo Data Model Access. Employee agents run as the user, so users need access to the action classes as well as the agent.
- **Slack:** the Agent Script carries the Slack connection (`connection slack:` at the end), so republishing keeps it. On a new org, install the agent in Slack once: Slack **Admin → Manage Agentforce → Review agent → Install Agent**, then add it to the workspace.
- **Edits in Agentforce Builder:** copy the Agent Script into `aiAuthoringBundles/Denali_Assistant/Denali_Assistant.agent` straight away. The org won't return Agent Script through a retrieve, so a Builder-only change is lost the next time `publish_agent.sh` publishes the repo's copy.
- **Action references:** instructions name actions as `{!@actions.<name>}` (Agentforce Builder's syntax), so each reference resolves to the reasoning action rather than being plain text.
- **Test before publishing:** `sf agent preview start --authoring-bundle Denali_Assistant --use-live-actions`, then `sf agent preview send`. `sf agent trace read` shows which actions ran.
- **Agent Script gotcha:** give reasoning actions verb-first names that differ from the subagent names (`check_all_accounts`, not `portfolio_risk`). With matching names the model tried the router's transition instead of the action, then answered with made-up accounts.

### Sales processes (`optional/`)
Opportunity stages follow the federal capture lifecycle, with Pwin as the probability:

| Stage | Pwin | Forecast | Gate |
| --- | --- | --- | --- |
| Identified | 5% | Pipeline | |
| Qualified | 10% | Pipeline | Pursue decision |
| Capture / Shaping | 20% | Pipeline | |
| Bid Decision | 30% | Pipeline | Bid / no-bid |
| Proposal Development | 40% | Pipeline | Color-team reviews; margin approval before submitting |
| Proposal Submitted | 50% | Best Case | The Margin Approval Required rule blocks reaching 50% below the floor without approval |
| Discussions / Negotiation | 75% | Commit | |
| Closed Won / Closed Lost / No Bid | 100 / 0 / 0 | Closed / Omitted | Loss Reason required on Closed Lost; No Bid stays out of win rates |

- **Two sales processes**, each with a record type and a sales path (key fields and guidance per stage):
  - **New Pursuit** (New Business, Recompete): every stage.
  - **Contract Growth** (Task Order, Option Exercise, Contract Modification): Identified → Proposal Development → Proposal Submitted → Discussions / Negotiation → closed. No shaping or bid decision under an existing contract.
- **Deploying only the sales pieces** (no Entitlement Management needed): deploy `optional/main/default/standardValueSets/OpportunityStage` and `OpportunityType`, `objects/Opportunity`, `pathAssistants` and the `Denali_Opportunity_Processes` permission set together, then assign the permission set. The stage set **replaces the org's Opportunity stages**; existing deals keep their old stage as an inactive value, so reset and reseed the demo data afterwards.
- **Seeding:** `04` gives each demo deal its record type by deal Type, when the record types exist.
- **Flow-created renewals** (Engagement Milestone Renewal Opp) get the creating user's default record type.

### Persona apps (`persona-apps/`)
Each persona has a **desktop app** and a phone-only **Mobile app**, so the phone's app switcher shows just the two Mobile apps. Both use the same Denali record pages, each app assigning them for its own form factor; other apps keep the org's default pages. Each persona's apps share a header color and logo (`persona-apps/contentassets`).

- **Denali Portfolio (General Manager):**
  - **Home:** both dashboards and Pricing Approvals.
  - **Pages:** Account (Denali Account), Opportunity (Path, Dynamic Forms, Guardrail and Competitor Intel), Contract (Contract Health), Project (timeline), Case (Denali Case).
  - **Tabs:** Account Command Center, Accounts, Opportunities, Forecasts, Contracts, Projects, Risks, Reports, Dashboards. The Command Center is also the first tab on a customer's Account page.
- **Denali Portfolio Mobile (phone):** opens on **Pricing Approvals** (an app page, since the mobile app doesn't use Lightning Home pages), then **Command Center** (the phone version, `accountCommandCenterMobile`), Accounts, Opportunities, Contracts, Projects, Risks, Dashboards.
- **Denali Delivery (Project Manager):**
  - **Home:** My Projects.
  - **Pages:** Account, Project, Deliverable (Supplier Update Review), Case (Denali Case: service lifecycle path, Impact Chain, SLA milestones and Knowledge).
  - **Tabs:** Projects, Deliverables, Deliverable Updates, Risks, Cases, Accounts, Reports. The Command Center is on the Account page.
- **Denali Delivery Mobile (phone):** opens on **My Projects**, then Projects, Deliverables, Deliverable Updates, Risks, Cases, Accounts.

**Roles** (`persona-apps/roles`), under the org's **CEO** role (most orgs have it; otherwise create it first):

```
CEO
└── General Manager
    ├── Capture & Business Development   (pursuits, capture plans, pricing)
    ├── Contracts Manager                (awards, funding, option exercises)
    ├── Program Management               (project managers)
    └── Service Delivery                 (cases, SLAs, Knowledge)
```

Records are shared org-wide (Opportunity is Public Read Only), so the roles don't change who sees what. They let managers edit their team's deals and run team reports, and Forecasts quotas need users to have one. Assign roles to demo users in Setup → Users.

The **Denali Account** page uses Dynamic Forms and a header, main area and right sidebar layout. The main area has tabs (Activity, Command Center, Details, Related, Competitor Intel); the sidebar has Account Supplier Updates, Account Suppliers, Account Team and the account's Slack channel. Its header is a role-specific **Dynamic Highlights Panel** (customers: Health, Tier, Status, Government, Strategic, Owner; suppliers: Account Role, Status, Phone, Website, Owner; competitors: Deals and Bookings Lost To, Status, Owner), falling back to the compact layout for accounts with no role. The Command Center tab shows for customers only (and opens first), and field sections and related lists show by Account Role:

| Role | Extra field sections | Related lists |
| --- | --- | --- |
| Customer | Customer Health | Opportunities, Assets, Account Plans, Contracts, Projects, Service Engagements, Cases, Risks |
| Supplier | None | Supplier Assignments, the deliverables they own |
| Competitor | Competitive Record | Opportunities lost to them, and where they're the incumbent |

### Standard layouts (`standard-layouts/`)
- **Opportunity:** Government Capture, Pricing & Margin, and Win / Loss sections. The Submit for Approval button is unhidden, and Approval History is added.
- **Contract:** Government Award, and Financials & Margin sections.
- **Case:** Service & Impact, Escalation, and Resolution sections. The closing and escalation validation rules need these fields on the page. The **Articles** related list is there too: the Knowledge component on the Denali Case page only offers **Attach to Case** when it is.
- **Contact:** a Government Contact section.
- **Account settings** (`objects/Account.object`): makes the **Denali Account** compact layout Account's default, so the record header shows Roles, Customer Health, Tier, Status, Government, Owner, Strategic, Executive Sponsor and Phone. It carries the org's other Account settings (feeds, history, sharing, search layouts, action overrides) unchanged. The compact layout itself, and the **Roles** text formula it uses (compact layouts can't show the multi-select Account Role), are in `force-app`.

These were built from the org this kit was developed in, so deploying them **replaces the org's layouts** for those four objects and **replaces Account's object-level settings**. Retrieve and compare them first on any other org.

### Permission sets
- **Demo Data Model Access:** objects, fields, tabs, Apex classes, and the Command Center tab.
- **Denali Persona Apps:** access to the four apps (desktop and Mobile) and the Mobile apps' own tabs (the two home pages and the mobile Command Center).
- **Demo Data Model - Service Cloud** (`Demo_Data_Model_Entitlements`, `optional/`): the Entitlement lookup, the Case SLA fields the Milestones panel and path use, the SLA Breached flag, and the Knowledge Details field. The System Administrator profile doesn't see the Case SLA fields on its own.
- **Denali Opportunity Processes** (`optional/`): the New Pursuit and Contract Growth record types.

## Before you start

### 1. Before deploying `force-app` (the deploy fails without these)
| Check | Why | Where |
| --- | --- | --- |
| **Edition:** Enterprise, Unlimited or Developer Edition with Sales Cloud; Lightning Experience; My Domain deployed | Lightning Web Components, Apex, approvals, Products, Contracts and Campaigns | Standard in those editions |
| **Sales Account Plans** on | The Denali Account page shows the Account Plans related list | Setup → Account Plans. Without them, remove the `rl_accountplans` item from `Denali_Portfolio_Account.flexipage-meta.xml` |
| **Einstein generative AI** on, with Prompt Builder | `force-app` includes the Pricing Rationale prompt template | Setup → Einstein Setup. Also turn on **Deploy prompt templates as active** if offered (`EinsteinGptSettings.enableEinsteinGPTDeployPromptTemplatesAsActive`), which saves activating it by hand |
| **2 free Change Data Capture slots** | The kit selects Deliverable and Deliverable Update for the live-updating components (standard orgs allow 5) | Setup → Change Data Capture |
| **Room for 13 tracked Opportunity fields** | Opportunity allows 20 history-tracked fields | Setup → Object Manager → Opportunity → Fields & Relationships → Set History Tracking |

**First deploy to a new org:** use `scripts/deploy_core_new_org.sh <alias>` instead of deploying `force-app` directly. The prompt template file carries the version identifiers of the org the kit was built in, and a new org rejects them. The script deploys a temporary copy of `force-app` with only the template's latest version and no identifiers, and leaves the repo unchanged. Add `--dry-run` to validate first. Later deploys to that org can use `force-app` as usual once you've retrieved the template back (it then carries that org's identifiers).

### 2. After deploying `force-app` (for things to work)
- **Path:** Setup → Path Settings → turn on, or the Opportunity page's Path is empty.
- **Prompt template:** activate **Pricing Rationale** in Prompt Builder (unless it deployed as active) and give users Prompt Template access. Without it, the Guardrail's Regenerate with Einstein button shows an error; everything else works.
- **Email deliverability:** Setup → Deliverability → All email, so the supplier update flows can send their emails.
- **Access:** run `01_verify_and_grant_access.apex` (it assigns Demo Data Model Access to you).

### 3. Before the later folders
| Folder | Needs first |
| --- | --- |
| `optional/` | **Entitlement Management** and **Lightning Knowledge** on. It also **replaces the Opportunity stages**, product picklists and Case Status and Priority values (see Sales processes), and switches Forecasts to **quarterly** periods, from last quarter to two ahead. Changing the period type deletes any existing quotas and adjustments |
| `ai/` | The Pricing Rationale template active |
| `dlrs/` | The **Declarative Lookup Rollup Summaries** package installed |
| `agentforce/` | Agentforce employee agents (Agentforce licences and the Agentforce (Default) agent) |
| `account-plans/` | Sales Account Plans on; afterwards, activate the Open Pipeline calculation (see Run it). For `08`'s action plans, also turn on **Action Plans** (Setup → Action Plans) |
| `persona-apps/` | `force-app` deployed |
| `standard-layouts/` | Nothing, but it **replaces** four standard layouts and Account's settings; compare first |

### The kit's own copies of edited pages
The Opportunity page in the original org also shows **Opportunity Currency** and the **Slack record channel**. The kit's copy leaves both out, because they need multiple currencies (which can't be turned off once on) and the Salesforce Slack integration. Deploying the kit's page to the original org would remove them there, so retrieve and compare first (see Maintaining the kit).

## Run it

### Option A: Salesforce CLI

```bash
sf org login web --alias demo
cd Denali-Defense                                  # this project folder

# 1. Core. For a first deploy to a new org, use scripts/deploy_core_new_org.sh demo (see Before you start)
sf project deploy start --source-dir force-app --target-org demo --dry-run   # validate first
sf project deploy start --source-dir force-app --target-org demo

# 2. Optional (clean demo org only; after enabling Entitlement Management)
sf project deploy start --source-dir optional --target-org demo

# 3. AI: first activate the "Pricing Rationale" template in Setup → Prompt Builder
sf project deploy start --source-dir ai --target-org demo

# 3b. Rollups: needs the Declarative Lookup Rollup Summaries package installed
sf project deploy start --source-dir dlrs --target-org demo

# 3c. Agentforce: the Denali Assistant employee agent. Its actions reuse force-app's controllers
sf project deploy start --source-dir agentforce/main/default/classes --target-org demo
scripts/publish_agent.sh demo                      # publish only reads the default folder; the script handles that

# 3d. Sales Account Plans: enable them in Setup first. The calculation deploys as Draft (Salesforce only
#     takes conditions in Draft) and Apex can't activate it, so activate it with the CLI
sf project deploy start --source-dir account-plans --target-org demo
sf data update record --target-org demo --sobject AccountPlanObjMeasCalcDef \
  --where "DeveloperName=Denali_Open_Pipeline" --values "Status=Active"

# 4. Persona apps
sf project deploy start --source-dir persona-apps --target-org demo
sf org assign permset --name Denali_Persona_Apps --target-org demo

# 5. Standard layouts: REPLACES the org's Opportunity, Contract, Case and Contact layouts
sf project deploy start --metadata-dir standard-layouts --target-org demo

# 6. Data
sf apex run --file scripts/apex/01_verify_and_grant_access.apex --target-org demo
sf apex run --file scripts/apex/02_seed_demo_data.apex         --target-org demo
sf apex run --file scripts/apex/04_seed_revenue_history.apex   --target-org demo
sf apex run --file scripts/apex/05_seed_activity_history.apex  --target-org demo
sf apex run --file scripts/apex/06_seed_account_plans.apex     --target-org demo   # only with Sales Account Plans
sf apex run --file scripts/apex/07_seed_products.apex          --target-org demo
sf apex run --file scripts/apex/08_seed_objective_action_plans.apex --target-org demo   # only with Action Plans and Sales Account Plans
sf apex run --file scripts/apex/09_seed_service_cloud.apex     --target-org demo   # only with optional/, run by a Knowledge user
sf apex run --file scripts/apex/11_seed_forecast_quotas.apex   --target-org demo   # only with optional/ and a forecast-enabled General Manager
sf apex run --file scripts/apex/03_recalculate_rollups.apex    --target-org demo
sf apex run --file scripts/apex/10_schedule_sla_breach_rollup.apex --target-org demo   # only with optional/; once per org

# Optional: run the Apex tests
sf apex run test --target-org demo --wait 20 --code-coverage \
  --class-names AccountCommandCenterControllerTest --class-names MarginGuardrailControllerTest \
  --class-names PortfolioControllersTest --class-names ProjectTimelineControllerTest --class-names DeliveryControllersTest \
  --class-names DlrsRollupsTest --class-names DenaliAgentActionsTest --class-names OpportunityAssetsTest
```

### Option B: no CLI (Workbench + Developer Console)

1. Go to workbench.developerforce.com, log in to the org, then open **Migration → Deploy**.
2. Deploy the zips in `workbench/` in order. Tick **Single Package** each time, and optionally **Check Only** first.
   1. `1_core_metadata.zip`
   2. `2_optional_metadata.zip`: clean demo org only, after enabling Entitlement Management.
   3. `3_ai_metadata.zip`: after activating the Pricing Rationale prompt template.
   4. `4_persona_apps.zip`: then assign the **Denali Persona Apps** permission set to demo users in Setup.
   5. `6_dlrs_rollups.zip`: after installing the DLRS package.
   6. `5_standard_layouts.zip`: replaces the four standard layouts.
3. Open the Developer Console, then **Debug → Open Execute Anonymous Window**. Run the scripts in order: `01`, `02`, `04`, `05`, `06` (with Sales Account Plans), `07`, `08` (with Action Plans), `09` (with `optional/`), `11` (with `optional/`), `03`, then `10` once (with `optional/`).
   - Filter the log on **Debug Only**. Results are logged at ERROR level so they're easy to find.

The zips are built from the folders. After changing the source, rebuild them with `sf project convert source --source-dir <folder> --output-dir <tmp>` and zip the output's contents, with `package.xml` at the root.

## The scripts

| Script | Purpose | Re-runnable |
| --- | --- | --- |
| `01_verify_and_grant_access.apex` | Confirms every object and field exists, reports which optional pieces are in place, assigns Demo Data Model Access to you, and makes a forecast-enabled General Manager that role's forecast manager | Yes |
| `02_seed_demo_data.apex` | Creates 3 customers, 2 suppliers, a competitor, 7 contacts, 4 opportunities, 2 activated contracts, 3 projects, 7 deliverables, 4 supplier updates, supplier assignments, project resources, 2 service engagements with milestones, 4 cases and 4 risks | Stops if seed data already exists |
| `04_seed_revenue_history.apex` | Adds the deals behind the dashboards: three quarters of bookings against the $5.5M quarterly target, so fiscal-year reporting has a trend. Won: $6.1M (111%) three quarters ago, counting `02`'s $4.2M Northwind award, then $4.6M (84%), then $3.7M (67%) last quarter. Lost to the incumbent, Vantage Federal: $0.8M, $2.4M, $3.3M, with loss reasons. One No Bid stays out of win rates. Quarters are relative to the seed date. `02`'s award closes eight months before the seed, so it lands in the earliest quarter only when you seed in the first two months of a quarter. Also adds one open fixed-price deal at 9%, below its 12% floor, for the approval demo | Yes. Matches deals by name and updates them |
| `05_seed_activity_history.apex` | Adds 11 tasks (calls, emails, open follow-ups) and 4 meetings to the demo records, so Activity timelines tell the story: the Sensor Fusion escalation at Northwind, Option Year 2 and the Denver outage at Federal Logistics Command, and the Zero Trust pricing at Aegis. Dates are relative to today, and open tasks are owned by whoever runs it | Yes. Replaces its own activities, matched by subject |
| `06_seed_account_plans.apex` | Adds a Sales Account Plan to each customer: a growth plan for Northwind, a retention plan for Federal Logistics Command and a Zero Trust capture plan for Aegis. Each has the account strategy and SWOT, objectives, and measures. Revenue measures are linked to the demo deals and calculated by Salesforce, so closing a deal moves its plan. Needs Sales Account Plans and `account-plans/` | Yes. Replaces the seeded accounts' plans |
| `07_seed_products.apex` | Adds a 15-product catalog with a list price in the Standard Price Book and a ceiling price in a **GSA Schedule** price book: 6 labor categories (hourly T&M rates), fixed-price solutions, annual managed services, training and documentation, and hardware. Activates the Standard Price Book. Prices line up with the deals (Managed Network Operations is $1.85M a year on the GSA Schedule, like FLC Option Year 2). Marks only the installed base as assetizable and creates Assets for the deals already won. Then puts 25 product lines on the 10 demo deals, priced from the GSA Schedule for GSA vehicle deals and the Standard Price Book otherwise. Each deal's lines add up to its seeded Amount exactly (Salesforce sets Amount from the lines), so dashboards, rollups and account plans don't change; the script logs any deal that doesn't match | Yes. Matches products by Product Code (`DD-…`) and replaces the deals' lines |
| `08_seed_objective_action_plans.apex` | Puts an Action Plan on six account plan objectives, so each has its steps as tasks with due dates: **Recovery Plan** (Sensor Fusion; FLC network reliability), **Account Growth** (Northwind task orders), **Option Exercise** (FLC Option Year 2), **Capture Plan** (Zero Trust: black hat, price-to-win, bid / no-bid, Pink/Red/Gold reviews) and **Margin Exception** (Zero Trust pricing). Creates and publishes the five `Denali_…` Action Plan templates the first time and reuses them after. Needs Action Plans and Sales Account Plans | Yes. Replaces the plans and their tasks; the templates stay. To change a template, mark its version Obsolete, delete it and re-run |
| `09_seed_service_cloud.apex` | Puts the demo cases under the **Denali Service SLA**: an entitlement on each Service Engagement, and SLA clocks relative to now (the Denver outage answered and inside its 24-hour resolution, the Sensor Fusion crash with its first response breached, the VPN request waiting on the customer with the clock stopped). Publishes four Knowledge articles that match the demo cases, and attaches two. Run it shortly before the demo | Yes. Replaces its entitlements and articles |
| `03_recalculate_rollups.apex` | Recalculates every lookup rollup across **all** records. With `dlrs/` deployed the rollups update in real time, so `03` becomes a backfill: run it after deploying DLRS onto existing data (DLRS only recalculates when a child changes) or if numbers drift. Also refreshes SLA Breaches through `SlaBreachRollup` when `optional/` is deployed | Yes |
| `10_schedule_sla_breach_rollup.apex` | Schedules `SlaBreachRollup` hourly, so SLA Breaches keeps up as milestones violate, and runs it once. The job runs as whoever schedules it. Needs `optional/`. A reset doesn't remove the schedule, so run it once per org | Yes. Replaces the existing schedule |
| `11_seed_forecast_quotas.apex` | Gives each forecast-enabled user in the General Manager role a $5.5M quota for last quarter and the next three (the forecast range), on the Opportunity Amount forecast type. Needs `optional/`'s forecast settings, and `01` for the forecast manager. Quotas aren't demo records, so `99` leaves them; `reset_demo.sh` reruns this so they follow the quarter | Yes. Updates existing quotas |
| `99_reset_demo_data.apex` | Deletes everything the seed scripts created, child-first, including 07's catalog and price book, plus Salesforce's own "Sample Case" records. Metadata stays. `scripts/reset_demo.sh` runs it and the whole reseed in order | Yes |

Notes:
- **Seed with or without flows:** the seed script fills the fields the flows would normally set (inherited Account and Contract, review stamps, Case → Risk), so the data is consistent either way.
- **Flows active during seeding:** you'll also get notifications, an extra Risk from the Sev 2 case, an option-reminder Task, and a renewal Opportunity. `99_reset` removes those too.
- **Picklist fallback:** values fall back to Salesforce defaults if the optional standard value sets weren't deployed. For example, the Opportunity stage becomes Qualification instead of Capture / Shaping.
- **Why `04` is separate:** anonymous Apex is capped at 32,000 characters, and `02` is close to that limit.

## Maintaining the kit
- **Entitlement processes can't be changed once cases have used them** (entitlement versioning is off, and turning it on can't be undone). To change Denali Service SLA after a demo, deploy it under a new name and point `09` at it.
- **Lightning pages are edited in App Builder too.** Before changing a page in the kit, retrieve it from the org (`sf project retrieve start -m FlexiPage:<name>`) and start from that copy: a deploy replaces the whole page.
- **Deploy order matters:**
  - The `ai/` flow needs the prompt template in the org and active.
  - `persona-apps/` needs its Lightning pages already deployed from `force-app`.
- **Changing the prompt template:** published template versions can't be edited in place, so a redeploy of changed text is silently ignored.
  - **To change the wording:** add a new `<templateVersions>` entry with the next `versionIdentifier` and point `activeVersionIdentifier` at it. The file carries this org's identifiers; `scripts/deploy_core_new_org.sh` strips them for a first deploy to a new org.
  - **Deploy error:** "cannot deactivate … referenced by another resource" means the file has no active version identifier.
- **Rollups:** with `dlrs/` deployed they're real time. Without it, Contract Current Margin, Revenue Recognized, account portfolio figures and competitor records are only as current as the last `03` run. To change a rollup, edit its `dlrs/main/default/customMetadata` record, or edit it in DLRS and retrieve it back into the project.
- **Standard layouts:** deploy only the layouts you mean to replace. Build a package with just those members, rather than the whole folder, if someone may have edited the others in Setup.
- **Component styling (SLDS 2):** the components' CSS uses SLDS 2 global styling hooks (`var(--slds-g-…, fallback)`) for colour, type, spacing and borders, so they follow the org's theme, including SLDS 2 and dark mode. Colours come from the semantic hooks in the [SLDS 2 styling hook index](https://www.lightningdesignsystem.com/2e1ef8501/p/98b493-styling-hook-index), not palette hooks: Green/Yellow/Red health and other status fills use `success-1`, `border-warning-1` and `error-1`; pale chips and notes use the feedback `*-container-1` hooks with the matching `on-*` text colour; bar tracks use `surface-container-3`, empty segments `disabled-container-2`, and tiles `surface-container-1`. The risk heatmap shades from `success-container-1` through `warning-container-1` and `warning-base-80` to `error-container-2`. SLDS 1 orgs don't define the feedback hooks, so they show the fallbacks. SVG colours are CSS classes, not JavaScript values. Spacing utility classes in the templates are the density-aware `slds-var-` versions, so padding and margins follow each user's Comfy/Compact setting. Sizes follow the SLDS 2 scale from the [Components for Web | Lightning Design System 2](https://www.figma.com/community/file/1399892502513202095/components-for-web-lightning-design-system-2) Figma kit: emphasis is semibold (`font-weight-6`), containers have `radius-border-2` corners, bars and pills use `radius-border-4` (which clamps to a pill), and spacing and dot or bar sizes snap to `spacing-*` and `sizing-*`. Fallbacks are the SLDS 2 (Cosmos) values. Check changes with `npx @salesforce-ux/slds-linter@latest lint force-app/main/default/lwc`; the 17 warnings left are layout values with no SLDS 2 equivalent (100% widths, max widths, line heights, the rationale's 3-line clamp, the margin marker's half-pixel centering).
- **Revenue Health target:** the $5.5M target is a static value on the gauge (a gauge can't read a quota). The same $5.5M is the General Manager's quarterly quota in Forecasts (`11`); change both together.

## Still manual (not in the kit)
- **Account Plan Objective status values.** The Status picklist starts empty; add values (for example On Track, At Risk, Achieved) in Object Manager if you want objective status.
- **Milestone actions** (warning and violation alerts) on the Denali Service SLA milestones.
- **Supplier portal:** Experience Cloud site, Supplier Portal profile, sharing set, external OWD, and portal field-level security.
- **Contract record type "Government Award"**, and the Expired / Terminated Contract Status values. The validation rules aren't gated by record type yet.
- **Case Reason → Type** field dependency.
- **Page layouts for other standard objects.** Account uses the Dynamic Forms page in the apps.
- **Files related list** on the Deliverable and Deliverable Update layouts.
- **Field history tracking** on the custom objects. History is enabled on each one, but no fields are selected. Opportunity's tracked fields are in the kit.

## Roadmap and TODOs

*Last updated 7 October 2026.*

| Discovery theme | Status |
| --- | --- |
| Missed revenue targets | Done. Revenue Health, capture-lifecycle stages with Pwin, and account plans with measures that move when deals close |
| Sliding margins and competition | Done. Margin floors and approvals, Guardrail, Competitor Intel, and a product catalog with GSA Schedule pricing |
| Lifecycle visibility | Mostly done. Installed-base assets, account plans with action plans, and activity history; the employee side is still thin |
| Mobility and channels | Partial. Phone-only Mobile apps for both personas; no supplier portal or customer self-service yet |
| Collaboration | Partial. Notifications, live updates, and Denali Assistant in Slack; Slack record alerts not working yet |

### Demo readiness
- [x] Browser walkthrough of both apps, desktop and phone
- [x] Live-update test across two windows
- [x] Duplicate FLC renewal pipeline removed. Flow #13 now skips a contract that already has an open opportunity, and the seed links the option opportunity to its contract
- [x] Demo starting state set by the seed scripts. **Reset before each demo:**
  - Run `scripts/reset_demo.sh` (or `scripts/reset_demo.sh <org-alias>`). It asks first, then runs `99_reset_demo_data.apex`, `02`, `04`, `05`, `06`, `07`, `08`, `09`, `11` and `03`, and stops at the first failure. This puts Zero Trust FFP back at Capture / Shaping at 9% with no approval, the supplier updates back to Pending, and every date relative to the demo day.
  - Open both dashboards and click **Refresh**. Dashboards show the data from their last refresh, not live data, so after a reseed or a live close they're stale until refreshed.
  - **Reseed in the quarter you demo in.** The seed puts last quarter's bookings in the quarter before the day it runs. Seed in September and demo in October, and Revenue Health's "last quarter" gauge shows the wrong quarter.
  - After any live close in the demo (for example FLC Option Year 2), reset again.
- [x] Unused Pricing Review queue deleted
- [x] Command Center tab shown on customer accounts only. Suppliers and competitors open on Details
- [x] Capture-lifecycle sales processes (New Pursuit, Contract Growth) with record types and Paths with guidance; Path on the Opportunity page
- [x] Activity history (`05`), account plans (`06`), product catalog with GSA Schedule pricing and deal lines (`07`), and action plans on objectives (`08`)
- [x] Closing a deal as won creates installed-base assets and moves its account plan; Create Contract on Win no longer duplicates contracts for option exercises
- [x] Win rate excludes No Bid; Command Center tree grid sizes its columns automatically
- [x] Live close of FLC Option Year 2 tried in the UI (asset created, one contract, Retention Plan to $1.85M), and by script with the contract update (Option Year 2, funding to $5.45M)
- [x] Health shows as colored dots in the Command Center's tree grid and as SLDS status icons in the Service table
- [x] Command Center contract cards share the full row; a single contract shows as a full-width strip
- [x] Supplier Updates, Suppliers and Team moved out of the Command Center into their own components, in the Denali Account page's sidebar
- [x] Activity panel on the Denali Account page (Activity tab)
- [x] Program Briefing ("Brief me on NDA-2026-001") tried on v7, the active version from Agentforce Builder. v7 only changed how the instructions reference actions and the router's off-topic and ambiguous routing
- [x] Case page: SLA (Denali Service SLA entitlement process, milestones, the clock stopping while Waiting on Customer), the Case Service Lifecycle path, and Knowledge articles for the demo cases (`09`)
- [x] Denali Case page: path above the tabs (Details, Related, Feed); Milestones, Impact Chain and Knowledge in the sidebar
- [ ] The sandbox still has an unused **Denali Government Support** entitlement process (the first version of Denali Service SLA). Salesforce won't change or deactivate it after cases used it; ignore it or delete it in Setup

### Roadmap (discovery themes 1, 3–5)
- [ ] **Supplier Portal (Experience Cloud):** suppliers submit Deliverable Updates themselves. The design is in `Demo_Org_Data_Model.md` (sharing set, edit lock, portal field-level security)
- [ ] **Mobile demo script:** a PM reviews a supplier update and a GM approves pricing, both on a phone
- [ ] **Agentforce Service Agent:** customer case intake and status on a portal. The org has the licences
- [x] **Agentforce employee agent:** Denali Assistant (`agentforce/`) is published (v8 active), given to users through the Denali Assistant Access permission set, and in Slack. Topics: Program Briefing (including open cases), Portfolio Risk, Pricing Approvals (with approve/reject), Delivery Status (including My Projects), Service Status (case briefings and open cases with SLA status)
- [ ] **Slack record alerts:** the workspace is connected and Denali Assistant works there. Still to do:
  - Flow's generic Slack actions (Send Message to Slack, Create Slack Channel) aren't available in the org yet, so project channels and custom alerts can't be built.
  - The cloned Opportunity Slack notification flows look for sales channel (Swarm) records, but channels are now linked as Slack Channel Related Records. Update the flows, or link channels the older way.
  - Deals Won points at a channel in another Slack team; Deals Won and Deals to Watch need channel IDs.
  - Track Next Step on Opportunity, or the Next Step Unchanged reminder fires daily for every open deal.
  - Messages in a record channel return "MESSAGE_EVENT NullPointerException" from Salesforce's Slack processing (the message still posts). Debug logs show nothing in the org; raise a support case.
- [x] **Forecasts quotas:** quarterly forecasts with a $5.5M quarterly quota for the General Manager (`11`), and a Forecasts tab in Denali Portfolio
- [ ] **Employee side of lifecycle visibility:** allocation and utilization by person from Project Resource
- [x] **Option exercise updates the contract:** winning an Option Exercise deal moves its contract's current period and next option date, and adds the deal to funded value (Opportunity Exercise Option flow)
- [ ] **Action plan for "Return Customer Health to Green":** the one seeded objective without an action plan
- [ ] **Post-award kickoff:** an Action Plan created on Closed Won (Contract Award Kickoff), if management wants post-award execution in the demo

### Kit hardening
- [x] Version control. The repository is initialised with the kit committed on `main`
- [x] Git remote added (`SF_Denali-Defense` on GitHub) and pushed. Work on branches from here, keeping `main` as the known-good demo
- [x] Replace `03_recalculate_rollups.apex` with Realtime DLRS rollups (`dlrs/`). `03` stays as a backfill. SLA Breaches moved to the hourly `SlaBreachRollup` job
- [x] Make `force-app` deployable to a new org: prerequisites in Before you start, `scripts/deploy_core_new_org.sh` for the prompt template, Track as Asset instead of the licensed Is Assetizable, and no multi-currency, Slack or historical-trending dependencies in the kit's metadata
- [ ] Test the kit end to end on a fresh org (Developer Edition, scratch org or new sandbox), following this README. Start with `scripts/deploy_core_new_org.sh <alias> --dry-run`. Not yet confirmed: that a new org accepts the stripped prompt template, and that the Unit of Measure field is standard everywhere
- [ ] Close the gaps under [Still manual](#still-manual-not-in-the-kit): Files related lists, field history on the custom objects, Government Award record type, Contract statuses, Case Reason dependency, milestone actions, Account Plan Objective statuses
- [ ] Use the org or user currency in the components, instead of hard-coded US dollars (the org has multi-currency on)
- [ ] Code quality:
  - Margin Guardrail controller coverage is 68% (only matters for a production deploy).
  - Add Jest tests for the components.
  - Keep `02_seed_demo_data.apex` under the 32,000-character anonymous Apex limit.
- [ ] Update the Salesforce CLI (2.152 → 2.153)

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| A dashboard shows old numbers after a reseed or live close | Dashboards don't refresh on their own. Click **Refresh** on the dashboard |
| A tab icon shows as a solid black square in the iOS mobile app | Its tab style is one of the five custom icons whose image has no transparency (Custom3, Custom7, Custom13 "Box", Custom28, Custom63); iOS draws the icon's silhouette from its transparency. Pick another style (the kit's object tabs use Flag, Cube, Form, Triangle, Stopwatch, People, Headset and Truck) |
| A dashboard fails in the mobile app with `undefined is not an object (evaluating 'b.id')` | The dashboard uses the **branding** color palette. In the mobile app it breaks charts that need several colors (donuts, stacked bars), though desktop is fine. Keep the dashboards on **unity** (Dashboard properties → Color Palette) |
| Revenue Health's gauge is near zero | The demo crossed into a new quarter since the last seed, so "last quarter" has no seeded bookings. Reset and reseed |
| "You've reached the maximum number of dynamic dashboards" | Both dashboards run as the viewer (dynamic). Enterprise Edition allows 5 per org and Unlimited 10. Delete unused dynamic dashboards, or set these to run as a fixed user |
| Contract Backlog or Contract Value look wrong | They read the Revenue Recognized rollup. Without `dlrs/`, run `03_recalculate_rollups.apex` |
| Lookup filter errors on `Is_Supplier__c` or `Is_Competitor__c` | Some orgs won't allow a lookup filter on a formula checkbox. Delete the `<lookupFilter>` block from the named field and redeploy; the fallback is a plain checkbox kept in sync with Account Role |
| "Entity type cannot be inserted: Entitlement" | `optional/` was deployed before enabling Entitlement Management |
| `ai/` deploy: "We can't find the Pricing_Rationale action" | The prompt template isn't in the org, or isn't active. Deploy `force-app`, activate it in Prompt Builder, then retry |
| `persona-apps/` deploy: "… is not a valid override for action View" | The Lightning pages aren't deployed yet. Deploy `force-app` first |
| `persona-apps/` deploy: "Can't remove form factor Small as an action override exists with that form factor" | The org has an older kit whose desktop apps were assigned pages for phone, and a deploy can't remove page assignments. In Lightning App Builder, open each Denali record page → **Activation…** → **App Default** and remove the **Phone** entries for Denali Portfolio and Denali Delivery (not the Mobile apps), then redeploy |
| Regenerate with Einstein fails | Einstein generative AI is off, the template is inactive, or the user lacks prompt template permissions |
| Components never show ● Live | Change Data Capture isn't enabled for the two objects (Setup → Change Data Capture), or you're in the mobile app, which has no streaming |
| A save fails with a DLRS error, or a rollup looks wrong | Check the rollup's record in Setup → Custom Metadata Types → Lookup Rollup Summary. To stop it immediately, set **Active** to false there (or in its `dlrs/` file and redeploy). Recalculate with DLRS's *Calculate* action or `03_recalculate_rollups.apex` |
| A field is missing from an Account header (Dynamic Highlights Panel) | The panel didn't render the **Roles** formula field in this org, though it saved without error. Use real fields in the panels; Roles exists only for the compact layout, which can't show the multi-select Account Role |
| The Knowledge component on a case won't attach an article | The Case layout is missing the **Articles** related list (`RelatedArticleList`). Deploy the Case layout from `standard-layouts/`, or add the list in the layout editor |
| Closing a case fails on Root Cause or Resolution Summary | The Case layout from `standard-layouts/` isn't deployed |
| An accepted supplier update needs undoing | The Accepted Update Locked rule blocks edits by design. Deactivate the rule, set the update back to Pending (clearing Reviewed By and Review Date), restore any Deliverable fields the Update Review flow changed, then reactivate the rule |

Picklist values use plain hyphens (for example `Sev 1 - Critical Outage`, `4 - Highly Likely`) rather than the en dashes in the spec, to avoid encoding issues. The Risk Score formula reads the leading digit, so it works either way.

## License

[MIT](LICENSE)
