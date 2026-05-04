/**
 * CacheService
 * ============
 * In-transaction cache store for expensive external API results.
 *
 * All caches are static — they live for the duration of one Apex transaction
 * (one batch execute() chunk).  They protect against duplicate API calls
 * within a single chunk and, for distance pairs, across re-runs on unchanged records.
 *
 * WHAT IS CACHED HERE
 * -------------------
 * | Cache              | Key format                              | Saves                          |
 * |--------------------|-----------------------------------------|--------------------------------|
 * | competitorByCity   | 'lat,lng'                               | Google computeInsights $0.005  |
 * | distanceByPair     | 'oLat,oLng>>dLat,dLng'                  | Google Distance Matrix $0.005  |
 *
 * WHAT IS CACHED ELSEWHERE
 * ------------------------
 * Text Search (placeId + coordinates) is cached as Api_GoogleMapsService.placeCache
 * because its value type (PlaceResult) is an inner class of that service.
 *
 * COST IMPACT
 * -----------
 * - competitorByCity: Market_Analysis__c has one row per city, so within a single
 *   chunk there are no duplicate city keys.  The cache becomes critical when
 *   multiple records share the same city (e.g. future Competitor_Store__c enrichment
 *   that groups by city before calling computeInsights).
 * - distanceByPair: Expansion sites repeatedly measured against the same DC/warehouse
 *   coordinates (same origin) benefit immediately — only the first call is billable.
 */
public with sharing class CacheService {

    // ── Competitor count per city ─────────────────────────────────────────────
    // Key: 'lat,lng'  →  Integer competitor count
    @TestVisible
    private static Map<String, Integer> competitorByCity = new Map<String, Integer>();

    // ── Driving distance per origin/destination pair ──────────────────────────
    // Key: 'originLat,originLng>>destLat,destLng'  →  Decimal km
    @TestVisible
    private static Map<String, Decimal> distanceByPair = new Map<String, Decimal>();

    // ── Competitor count ──────────────────────────────────────────────────────

    /** Builds the cache key for a city centre coordinate pair. */
    public static String cityKey(Decimal lat, Decimal lng) {
        return String.valueOf(lat) + ',' + String.valueOf(lng);
    }

    public static Boolean hasCompetitorCount(String key) {
        return competitorByCity.containsKey(key);
    }

    public static Integer getCompetitorCount(String key) {
        return competitorByCity.get(key);
    }

    public static void putCompetitorCount(String key, Integer count) {
        if (key != null && count != null) {
            competitorByCity.put(key, count);
        }
    }

    // ── Driving distance ──────────────────────────────────────────────────────

    /**
     * Builds the cache key for an origin/destination pair.
     * @param origin  'lat,lng' string for the origin point.
     * @param dest    'lat,lng' string for the destination point.
     */
    public static String distanceKey(String origin, String dest) {
        return origin + '>>' + dest;
    }

    public static Boolean hasDistance(String key) {
        return distanceByPair.containsKey(key);
    }

    public static Decimal getDistance(String key) {
        return distanceByPair.get(key);
    }

    public static void putDistance(String key, Decimal km) {
        if (key != null && km != null) {
            distanceByPair.put(key, km);
        }
    }

    // ── Test helpers ──────────────────────────────────────────────────────────

    /** Clears all in-transaction caches. Use in @testSetup or test teardown. */
    @TestVisible
    public static void clearAll() {
        competitorByCity.clear();
        distanceByPair.clear();
    }
}