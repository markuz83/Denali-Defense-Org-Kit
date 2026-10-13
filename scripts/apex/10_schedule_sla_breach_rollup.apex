// 10_schedule_sla_breach_rollup.apex
// Schedules SlaBreachRollup hourly (on the hour) so Case SLA Breached and Service Engagement SLA Breaches stay current
// as milestones violate, and runs it once now.
// - Needs optional/ deployed (the class and Entitlement Management).
// - Re-runnable: replaces the existing schedule. The job runs as whoever runs this script.

String jobName = 'Denali SLA Breach Rollup';
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :jobName]) {
    System.abortJob(ct.Id);
}
String jobId = System.schedule(jobName, '0 0 * * * ?', new SlaBreachRollup());
new SlaBreachRollup().execute(null);

System.debug(LoggingLevel.ERROR, '===== SLA BREACH ROLLUP SCHEDULED =====');
System.debug(LoggingLevel.ERROR, 'Job ' + jobId + ' runs hourly. Next: ' +
    [SELECT NextFireTime FROM CronTrigger WHERE Id = :jobId].NextFireTime);
