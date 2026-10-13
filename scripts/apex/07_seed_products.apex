// 07_seed_products.apex
// Adds Denali Defense's catalog: labor categories (T&M, hourly), fixed-price solutions, managed
// services (annual), training and documentation, and hardware. Every product gets a list price in
// the Standard Price Book and a lower ceiling price in a "GSA Schedule" price book.
// Prices line up with the demo deals: Managed Network Operations is $1.85M a year on the GSA
// Schedule (FLC Option Year 2), Zero Trust Architecture Implementation lists at $2.4M (Aegis
// Zero Trust Production), and a Technical Manual Set is $180K (the Northwind deliverable).
//
// - Activates the Standard Price Book, which new orgs ship inactive.
// - Families and units fall back to blank if optional/'s Product2Family and
//   QuantityUnitOfMeasure value sets aren't deployed.
// - Puts product lines on the 10 demo deals, so they can be shown as quotes. Salesforce sets an
//   opportunity's Amount to the total of its lines, so every deal's lines add up to its seeded
//   Amount exactly and the dashboards, rollups and account plans don't move. GSA Schedule deals
//   price from the GSA Schedule; the rest from the Standard Price Book. Run after 02 and 04.
// - Only the installed base has Track as Asset ticked: hardware, the software license and the annual
//   services. Labor, implementations, training and manuals don't. The won deals' tracked lines
//   become Assets (OpportunityAssets, the same class the Create Assets on Win flow uses), because
//   02 and 04 won them before they had lines.
// - Re-runnable: products are matched by Product Code (all start "DD-"), price book entries are
//   updated in place, and the deals' lines are replaced. 99_reset removes them.

String pv(Schema.SObjectField f, String preferred) {
    for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) {
        if (e.isActive() && e.getValue() == preferred) return preferred;
    }
    return null;
}

// Columns: code, name, family, unit, list price, GSA Schedule price, description
List<List<String>> catalog = new List<List<String>>{
    // Labor categories: T&M rates per hour
    new List<String>{ 'DD-LC-PM', 'Program Manager III', 'Professional Services', 'Hour', '245', '218', 'Leads cost, schedule and performance on programs over $10M. Secret clearance.' },
    new List<String>{ 'DD-LC-SE', 'Systems Engineer II', 'Professional Services', 'Hour', '195', '174', 'Requirements, architecture and integration for sensor and network systems.' },
    new List<String>{ 'DD-LC-SWE', 'Software Engineer III', 'Professional Services', 'Hour', '185', '165', 'Develops and integrates mission software, including sensor fusion.' },
    new List<String>{ 'DD-LC-CYB', 'Cybersecurity Analyst II', 'Professional Services', 'Hour', '175', '156', 'Zero-trust engineering, RMF packages and continuous monitoring. Secret clearance.' },
    new List<String>{ 'DD-LC-NET', 'Network Engineer II', 'Professional Services', 'Hour', '160', '142', 'Designs and operates enterprise and depot networks.' },
    new List<String>{ 'DD-LC-TW', 'Technical Writer II', 'Professional Services', 'Hour', '110', '98', 'Technical manuals, operator guides and CDRL documentation.' },
    // Fixed-price solutions
    new List<String>{ 'DD-SOL-SENS', 'Sensor Integration Package', 'Solutions', 'Site', '1450000', '1305000', 'Integrates and certifies the modernized sensor suite at one site.' },
    new List<String>{ 'DD-SOL-FUS', 'Sensor Fusion Software License', 'Solutions', 'Site', '350000', '315000', 'Perpetual license for the sensor fusion software at one site.' },
    new List<String>{ 'DD-SOL-ZTA', 'Zero Trust Architecture Implementation', 'Solutions', 'Each', '2400000', '2160000', 'Designs and implements a zero-trust architecture for one enclave, through authority to operate.' },
    // Managed services: annual
    new List<String>{ 'DD-MS-NOC', 'Managed Network Operations', 'Managed Services', 'Year', '1950000', '1850000', '24x7 network operations for one region, with SLAs and monthly reporting.' },
    new List<String>{ 'DD-MS-SUS', 'Sensor Sustainment', 'Managed Services', 'Year', '800000', '720000', 'Field support, spares and software updates for fielded sensors.' },
    // Training and documentation
    new List<String>{ 'DD-TRN-OPR', 'Operator Training Course', 'Training & Documentation', 'Course', '48000', '43200', 'Five-day operator course for up to 12 students, on site.' },
    new List<String>{ 'DD-TRN-MAN', 'Technical Manual Set', 'Training & Documentation', 'Each', '180000', '162000', 'Operator and maintenance manuals for one system, delivered as CDRLs.' },
    // Hardware
    new List<String>{ 'DD-HW-NODE', 'Ruggedized Sensor Node', 'Hardware', 'Each', '62500', '56250', 'MIL-STD-810 sensor node with secure boot.' },
    new List<String>{ 'DD-HW-GW', 'Edge Fusion Gateway', 'Hardware', 'Each', '38000', '34200', 'Edge processor that runs sensor fusion close to the sensors.' }
};

// The customer's installed base: what Denali supports, renews or exercises options on.
Set<String> installedBase = new Set<String>{ 'DD-HW-NODE', 'DD-HW-GW', 'DD-SOL-FUS', 'DD-MS-NOC', 'DD-MS-SUS' };

Pricebook2 standard = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
if (!standard.IsActive) {
    standard.IsActive = true;
    update standard;
}
List<Pricebook2> gsaBooks = [SELECT Id FROM Pricebook2 WHERE Name = 'GSA Schedule' AND IsStandard = false LIMIT 1];
Pricebook2 gsa = gsaBooks.isEmpty() ? new Pricebook2(Name = 'GSA Schedule') : gsaBooks[0];
gsa.IsActive = true;
gsa.Description = 'GSA Multiple Award Schedule ceiling prices for federal task orders. About 10% below list.';
upsert gsa;

// Products: match by code so a re-run updates them.
Map<String, Product2> byCode = new Map<String, Product2>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode LIKE 'DD-%']) byCode.put(p.ProductCode, p);
List<Product2> products = new List<Product2>();
for (List<String> row : catalog) {
    Product2 p = byCode.containsKey(row[0]) ? byCode.get(row[0]) : new Product2(ProductCode = row[0]);
    p.Name = row[1];
    p.Family = pv(Product2.Family, row[2]);
    p.QuantityUnitOfMeasure = pv(Product2.QuantityUnitOfMeasure, row[3]);
    p.Description = row[6];
    p.Track_as_Asset__c = installedBase.contains(row[0]);
    // Keep the standard Is Assetizable in step where it exists (Industries and Revenue Cloud orgs).
    if (Product2.SObjectType.getDescribe().fields.getMap().containsKey('isassetizable')) {
        p.put('IsAssetizable', p.Track_as_Asset__c);
    }
    p.IsActive = true;
    products.add(p);
}
upsert products;

// Price book entries: the standard one must exist before a custom price book's entry.
Map<String, PricebookEntry> entries = new Map<String, PricebookEntry>();
for (PricebookEntry e : [SELECT Id, Pricebook2Id, Product2Id FROM PricebookEntry WHERE Product2Id IN :products]) {
    entries.put(e.Pricebook2Id + ':' + e.Product2Id, e);
}
for (Id bookId : new List<Id>{ standard.Id, gsa.Id }) {
    List<PricebookEntry> batch = new List<PricebookEntry>();
    for (Integer i = 0; i < catalog.size(); i++) {
        Decimal price = Decimal.valueOf(bookId == standard.Id ? catalog[i][4] : catalog[i][5]);
        String key = bookId + ':' + products[i].Id;
        PricebookEntry e = entries.containsKey(key)
            ? entries.get(key)
            : new PricebookEntry(Pricebook2Id = bookId, Product2Id = products[i].Id, UseStandardPrice = false);
        e.UnitPrice = price;
        e.IsActive = true;
        batch.add(e);
    }
    upsert batch;
}

// ---------------------------------------------------------------- Lines on the demo deals
// Columns: deal, price book (List or GSA), then product code / quantity / sales price groups.
// A blank sales price means the price book price. Every deal's lines total its seeded Amount.
List<List<String>> lines = new List<List<String>>{
    // $4.2M fixed price: two sites integrated and licensed, manuals, training, gateways
    new List<String>{ 'NDA - Integrated Sensor Modernization', 'List',
        'DD-SOL-SENS', '2', '', 'DD-SOL-FUS', '2', '', 'DD-TRN-MAN', '1', '', 'DD-TRN-OPR', '4', '', 'DD-HW-GW', '6', '' },
    new List<String>{ 'NDA - Sensor Sustainment Task Order 3', 'List', 'DD-MS-SUS', '2', '' },
    new List<String>{ 'NDA - Operator Training Task Order', 'List', 'DD-TRN-OPR', '10', '', 'DD-TRN-MAN', '4', '' },
    // Base year priced $50K under the GSA ceiling to win the recompete
    new List<String>{ 'FLC - Managed Network Operations', 'GSA', 'DD-MS-NOC', '1', '1800000' },
    new List<String>{ 'FLC - Network Ops Option Year 2', 'GSA', 'DD-MS-NOC', '1', '' },
    new List<String>{ 'FLC - Surge Network Support Mod', 'GSA', 'DD-LC-PM', '500', '', 'DD-LC-SE', '1200', '', 'DD-LC-NET', '4100', '' },
    new List<String>{ 'FLC - Depot Automation Study', 'GSA', 'DD-LC-PM', '700', '', 'DD-LC-SWE', '3000', '', 'DD-LC-SE', '2600', '' },
    new List<String>{ 'Aegis - Zero Trust Production (FFP)', 'List', 'DD-SOL-ZTA', '1', '' },
    new List<String>{ 'Aegis - Zero Trust Prototype (OTA)', 'List', 'DD-LC-PM', '300', '', 'DD-LC-SE', '1700', '', 'DD-LC-SWE', '2000', '', 'DD-LC-CYB', '1000', '' },
    new List<String>{ 'Aegis - Cyber Range Pilot', 'List', 'DD-LC-PM', '500', '', 'DD-LC-SE', '3000', '', 'DD-LC-SWE', '4000', '', 'DD-LC-CYB', '4300', '' }
};

// Seeded deals live on "[demo-seed]" accounts; Description is a long text area, so check in Apex.
Set<Id> acctIds = new Set<Id>();
for (Account a : [SELECT Id, Description FROM Account]) {
    if (a.Description != null && a.Description.contains('[demo-seed]')) acctIds.add(a.Id);
}
Set<String> dealNames = new Set<String>();
for (List<String> row : lines) dealNames.add(row[0]);
Map<String, Opportunity> deals = new Map<String, Opportunity>();
for (Opportunity o : [SELECT Id, Name, Amount FROM Opportunity WHERE AccountId IN :acctIds AND Name IN :dealNames]) {
    deals.put(o.Name, o);
}

Map<String, Id> entryId = new Map<String, Id>();   // "List:DD-…" or "GSA:DD-…"
Map<String, Decimal> entryPrice = new Map<String, Decimal>();
List<Id> books = new List<Id>{ standard.Id, gsa.Id };
for (PricebookEntry e : [SELECT Id, UnitPrice, Pricebook2.IsStandard, Product2.ProductCode FROM PricebookEntry
                         WHERE Product2Id IN :products AND Pricebook2Id IN :books]) {
    String key = (e.Pricebook2.IsStandard ? 'List' : 'GSA') + ':' + e.Product2.ProductCode;
    entryId.put(key, e.Id);
    entryPrice.put(key, e.UnitPrice);
}

// A deal's price book can only change once it has no lines, so clear them first.
delete [SELECT Id FROM OpportunityLineItem WHERE OpportunityId IN :deals.values()];
List<Opportunity> priced = new List<Opportunity>();
List<OpportunityLineItem> items = new List<OpportunityLineItem>();
List<String> mismatched = new List<String>();
for (List<String> row : lines) {
    Opportunity o = deals.get(row[0]);
    if (o == null) continue;   // 04 hasn't run
    String book = row[1];
    priced.add(new Opportunity(Id = o.Id, Pricebook2Id = book == 'GSA' ? gsa.Id : standard.Id));
    Decimal total = 0;
    for (Integer i = 2; i < row.size(); i += 3) {
        String key = book + ':' + row[i];
        Decimal qty = Decimal.valueOf(row[i + 1]);
        Decimal price = String.isBlank(row[i + 2]) ? entryPrice.get(key) : Decimal.valueOf(row[i + 2]);
        items.add(new OpportunityLineItem(OpportunityId = o.Id, PricebookEntryId = entryId.get(key),
            Quantity = qty, UnitPrice = price));
        total += qty * price;
    }
    if (total != o.Amount) mismatched.add(o.Name + ' (lines ' + total.format() + ', Amount ' + o.Amount.format() + ')');
}
update priced;
insert items;

// Installed base for the deals already won (later wins get theirs from the flow).
Set<Id> won = new Set<Id>();
for (Opportunity o : [SELECT Id FROM Opportunity WHERE Id IN :deals.values() AND IsWon = true]) won.add(o.Id);
List<Asset> assets = OpportunityAssets.createFor(won);

System.debug(LoggingLevel.ERROR, 'Products: ' + products.size() + ' in the Standard Price Book and the GSA Schedule ('
    + (products.size() - byCode.size()) + ' added, ' + byCode.size() + ' updated). ' + items.size() + ' lines on '
    + priced.size() + ' deals. ' + assets.size() + ' assets from won deals.' + (mismatched.isEmpty() ? '' : ' Lines differ from the seeded Amount: ' + String.join(mismatched, '; ')));
