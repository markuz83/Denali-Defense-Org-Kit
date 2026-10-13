// 11_seed_forecast_quotas.apex
// Gives the General Manager a $5.5M quarterly bookings quota in Forecasts, so the target the
// Revenue Health gauge shows is a real quota with attainment.
// - One quota per quarter in the forecast range (last quarter and the next three), for every
//   forecast-enabled user in the General Manager role, on the active Opportunity Amount
//   forecast type. Quarters come from the org's fiscal periods.
// - Needs Forecasts on with quarterly periods (optional/main/default/settings/Forecasting), the
//   General Manager role (persona-apps/), and the user's Allow Forecasting checkbox.
// - The role also needs a forecast manager (Setup -> Forecasts Hierarchy); 01 sets it. It's a setup
//   record, so it can't change in the same transaction as the quotas.
// - Re-runnable: updates the amount on existing quotas instead of adding new ones. Quotas aren't
//   demo records, so 99 leaves them; rerun this after a quarter rolls over.

Decimal quarterlyQuota = 5500000;

List<ForecastingType> types = [SELECT Id, MasterLabel FROM ForecastingType WHERE IsActive = true AND IsAmount = true AND DeveloperName = 'OpportunityAmount' LIMIT 1];
Assert.isFalse(types.isEmpty(), 'Turn on Forecasts with the Opportunity Amount forecast type first.');
Id forecastType = types[0].Id;

Date thisQuarter = [SELECT StartDate FROM Period WHERE Type = 'Quarter' AND StartDate <= TODAY AND EndDate >= TODAY LIMIT 1].StartDate;
List<Date> quarters = new List<Date>();
for (Period p : [SELECT StartDate FROM Period WHERE Type = 'Quarter' AND StartDate >= :thisQuarter.addMonths(-3) ORDER BY StartDate LIMIT 4]) {
    quarters.add(p.StartDate);
}

List<User> managers = [SELECT Id, Name FROM User WHERE IsActive = true AND ForecastEnabled = true AND UserRole.DeveloperName = 'General_Manager'];
if (managers.isEmpty()) {
    System.debug(LoggingLevel.ERROR, 'No forecast-enabled user in the General Manager role. Give the GM that role and tick Allow Forecasting, then rerun.');
    return;
}

Map<String, ForecastingQuota> existing = new Map<String, ForecastingQuota>();
for (ForecastingQuota q : [SELECT Id, QuotaOwnerId, StartDate FROM ForecastingQuota
                           WHERE ForecastingTypeId = :forecastType AND QuotaOwnerId IN :managers AND StartDate IN :quarters]) {
    existing.put(q.QuotaOwnerId + ':' + q.StartDate, q);
}

Boolean multiCurrency = Schema.SObjectType.ForecastingQuota.fields.getMap().containsKey('currencyisocode');
String corporateCurrency = multiCurrency ? (String) Database.query('SELECT IsoCode FROM CurrencyType WHERE IsCorporate = true LIMIT 1')[0].get('IsoCode') : null;

List<ForecastingQuota> toSave = new List<ForecastingQuota>();
Integer added = 0;
for (User u : managers) {
    for (Date q : quarters) {
        ForecastingQuota quota = existing.get(u.Id + ':' + q);
        if (quota == null) {
            quota = new ForecastingQuota(QuotaOwnerId = u.Id, ForecastingTypeId = forecastType, StartDate = q);
            if (multiCurrency) quota.put('CurrencyIsoCode', corporateCurrency);
            added++;
        }
        quota.QuotaAmount = quarterlyQuota;
        toSave.add(quota);
    }
}
upsert toSave;
if ([SELECT ForecastUserId FROM UserRole WHERE DeveloperName = 'General_Manager' LIMIT 1].ForecastUserId == null) {
    System.debug(LoggingLevel.ERROR, 'The General Manager role has no forecast manager yet: run 01_verify_and_grant_access.apex.');
}

List<String> names = new List<String>();
for (User u : managers) names.add(u.Name);
System.debug(LoggingLevel.ERROR, 'Forecast quotas: $' + quarterlyQuota.format() + ' a quarter for ' + String.join(names, ', ') + ', quarters starting '
    + quarters[0].format() + ' to ' + quarters[quarters.size() - 1].format() + ' (' + added + ' added, ' + (toSave.size() - added) + ' updated).');
