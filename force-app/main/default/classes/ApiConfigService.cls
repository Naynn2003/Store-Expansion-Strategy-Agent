/**
 * ApiConfigService
 * ================
 * Single-responsibility service for reading API_Config__mdt activation flags.
 *
 * DESIGN INTENT
 * -------------
 * Service classes (Api_GoogleMapsService, Api_BestTimeService, Api_GrowthRateService)
 * use Named Credentials for secrets — no API key ever touches Apex code.
 * They only need to know whether an integration is switched ON or OFF.
 * This class provides that single Boolean query and nothing more.
 *
 * This replaces the previous pattern of calling DynamicDataService.getConfig()
 * (which returned the full MDT record including the plaintext API_Key__c field)
 * inside service classes that no longer need the key value at all.
 *
 * CACHING
 * -------
 * Each provider name is queried at most once per Apex transaction.
 * Suitable for use inside batch execute() chunks.
 */
public with sharing class ApiConfigService {

    @TestVisible
    private static Map<String, Boolean> activeMap = new Map<String, Boolean>();

    /**
     * Returns true when the API_Config__mdt record for the given DeveloperName
     * has Is_Active__c = true.  Returns false for missing or inactive records.
     *
     * @param providerName  DeveloperName of the API_Config__mdt record
     *                      (e.g. 'World_Bank', 'Google_Maps', 'BestTime').
     */
    public static Boolean isActive(String providerName) {
        if (activeMap.containsKey(providerName)) {
            return activeMap.get(providerName);
        }

        // CMT records are deployment data — accessible to all running users by platform contract.
        // Guard included for PMD ApexCRUDViolation compliance.
        Boolean active = false;
        if (Schema.sObjectType.API_Config__mdt.isAccessible()) {
            List<API_Config__mdt> recs = [
                SELECT Is_Active__c
                FROM   API_Config__mdt
                WHERE  DeveloperName = :providerName
                LIMIT  1
            ];
            active = !recs.isEmpty() && recs[0].Is_Active__c;
        }

        activeMap.put(providerName, active);
        return active;
    }

    /** Clears the in-transaction cache. Use in test teardown. */
    @TestVisible
    public static void clearCache() {
        activeMap.clear();
    }
}