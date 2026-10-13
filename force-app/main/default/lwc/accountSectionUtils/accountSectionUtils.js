// Helpers shared by the Account Command Center and the account section components placed
// alongside it (accountSupplierUpdates, accountSuppliers, accountTeam).

export const url = (id) => (id ? `/${id}` : null);

// Salesforce percent fields hold 40 for 40%; lightning-datatable's percent type expects 0.4.
export const pct = (v) => (v === null || v === undefined ? null : v / 100);

export function reduceError(error) {
    if (!error) return 'Unknown error';
    if (Array.isArray(error.body)) return error.body.map((e) => e.message).join(', ');
    return error.body?.message || error.message || 'Unknown error';
}
