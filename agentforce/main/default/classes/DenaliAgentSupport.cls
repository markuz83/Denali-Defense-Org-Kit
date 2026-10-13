/**
 * Shared helpers for the Denali Assistant agent actions: finding a record by the name a user
 * typed, record links, and the JSON each action hands back to the agent.
 */
public with sharing class DenaliAgentSupport {

    public static final Integer MATCH_LIMIT = 5;

    public class Match {
        public SObject record;
        public String message;   // set when there is no single match
    }

    /**
     * Finds one record by name: an exact match wins, otherwise a single partial match.
     * Queries run in user mode, so the agent only finds what the user can see.
     */
    public static Match findByName(String sobjectName, String fields, String name, String label) {
        Match m = new Match();
        String trimmed = name == null ? '' : name.trim();
        if (String.isBlank(trimmed)) {
            m.message = 'No ' + label + ' name given. To look across every account, use the Portfolio Risk action.';
            return m;
        }
        Map<String, Object> binds = new Map<String, Object>{
            'exact' => trimmed,
            'pattern' => '%' + trimmed.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%'
        };
        List<SObject> exact = Database.queryWithBinds(
            'SELECT ' + fields + ' FROM ' + sobjectName + ' WHERE Name = :exact LIMIT 2',
            binds, AccessLevel.USER_MODE);
        if (exact.size() == 1) {
            m.record = exact[0];
            return m;
        }
        List<SObject> matches = Database.queryWithBinds(
            'SELECT ' + fields + ' FROM ' + sobjectName + ' WHERE Name LIKE :pattern ORDER BY Name LIMIT ' + (MATCH_LIMIT + 1),
            binds, AccessLevel.USER_MODE);
        if (matches.size() == 1) {
            m.record = matches[0];
        } else if (matches.isEmpty()) {
            m.message = 'No ' + label + ' matches \'' + trimmed + '\'.';
        } else {
            List<String> names = new List<String>();
            for (Integer i = 0; i < Math.min(matches.size(), MATCH_LIMIT); i++) {
                names.add((String) matches[i].get('Name'));
            }
            m.message = '\'' + trimmed + '\' matches several records: ' + String.join(names, ', ')
                + (matches.size() > MATCH_LIMIT ? ' and more' : '')
                + '. Ask which one they mean. This is a name search, not a full list.';
        }
        return m;
    }

    public static String recordUrl(Id recordId) {
        return URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/' + recordId + '/view';
    }

    public static String toJson(Object value) {
        return JSON.serialize(value, true);   // drop nulls to keep the agent's context small
    }
}
