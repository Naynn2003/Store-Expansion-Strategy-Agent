/**
 * AgentChatController
 * Routes chat messages to the real Agentforce agent
 * "Store Expansion Strategy Agent" (API name: Store_Expansion_Strategy_Agent)
 * via the Agentforce Agent REST API.
 *
 * Auth: OAuth 2.0 client credentials flow using the External Client App
 *       values stored in the API_Config__mdt record labelled "Agentforce"
 *       (API_Key__c = Consumer Key, Consumer_Secret__c = Consumer Secret,
 *       Base_URL__c = My Domain URL, Is_Active__c = true).
 *
 * Session lifecycle:
 *   - First call creates a session and returns the sessionId.
 *   - Subsequent calls pass the sessionId so conversation context is kept.
 */
public with sharing class AgentChatController {

    private static final String AGENT_DEVELOPER_NAME = 'Store_Expansion_Strategy_Agent';
    private static final String AGENT_API_BASE_URL   = 'https://api.salesforce.com/einstein/ai-agent/v1';
    private static final Integer TIMEOUT_MS          = 30000;

    // ── Public AuraEnabled entry point ─────────────────────────────────────────

    /**
     * @param message   The user's chat message text.
     * @param sessionId Existing agent session ID (empty string on first call).
     * @return JSON string: { "reply": "...", "sessionId": "..." }
     */
    @AuraEnabled
    public static String chat(String message, String sessionId) {
        if (String.isBlank(message)) {
            return toJson('Please enter a question.', sessionId);
        }

        API_Config__mdt cfg = getAgentConfig();
        if (cfg == null || String.isBlank(cfg.API_Key__c) || String.isBlank(cfg.Consumer_Secret__c) ||
            String.isBlank(cfg.Base_URL__c) || cfg.API_Key__c.startsWith('REPLACE') ||
            cfg.Consumer_Secret__c.startsWith('REPLACE')) {
            return toJson(
                '\u274C Agent not configured. Update the API Config record named "Agentforce" with ' +
                'the External Client App consumer key, secret, and My Domain URL, then set Is Active = true.',
                ''
            );
        }

        String baseUrl = cfg.Base_URL__c;
        String token = getOAuthToken(cfg);
        if (token == null) {
            return toJson(
                '\u274C Unable to obtain an access token. Check the External Client App consumer key, ' +
                'secret, Run As user, and My Domain URL.',
                ''
            );
        }

        // Create session on first turn
        String activeSession = sessionId;
        if (String.isBlank(activeSession)) {
            SessionResult sr = createSession(token, baseUrl);
            if (!sr.success) {
                return toJson('\u274C Agent session error: ' + sr.error, '');
            }
            activeSession = sr.sessionId;
        }

        // Send message and get reply
        String reply = sendMessage(token, baseUrl, activeSession, message);
        return toJson(reply, activeSession);
    }

    // ── OAuth token exchange ───────────────────────────────────────────────────

    private static API_Config__mdt getAgentConfig() {
        List<API_Config__mdt> configs = [
            SELECT API_Key__c, Consumer_Secret__c, Base_URL__c
            FROM   API_Config__mdt
            WHERE  Label = 'Agentforce'
              AND  Is_Active__c = true
            LIMIT  1
        ];
        return configs.isEmpty() ? null : configs[0];
    }

    private static String getOAuthToken(API_Config__mdt cfg) {
        if (cfg == null || String.isBlank(cfg.Base_URL__c)) {
            return null;
        }

        String tokenEndpoint = buildTokenEndpoint(cfg.Base_URL__c);
        if (tokenEndpoint == null) {
            return null;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(tokenEndpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setTimeout(10000);
        req.setBody(
            'grant_type=client_credentials' +
            '&client_id='     + EncodingUtil.urlEncode(cfg.API_Key__c,          'UTF-8') +
            '&client_secret=' + EncodingUtil.urlEncode(cfg.Consumer_Secret__c,  'UTF-8')
        );

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                Map<String, Object> data =
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                return (String) data.get('access_token');
            }
            System.debug('OAuth token error HTTP ' + res.getStatusCode() + ': ' + res.getBody());
        } catch (Exception e) {
            System.debug('OAuth token callout exception: ' + e.getMessage());
        }
        return null;
    }

    @TestVisible
    private static String buildTokenEndpoint(String baseUrl) {
        String normalizedBaseUrl = normalizeBaseUrl(baseUrl);
        return normalizedBaseUrl == null ? null : normalizedBaseUrl + '/services/oauth2/token';
    }

    private static String normalizeBaseUrl(String baseUrl) {
        if (String.isBlank(baseUrl)) {
            return null;
        }
        return baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
    }

    // ── Session result wrapper ──────────────────────────────────────────────────

    private class SessionResult {
        Boolean success = false;
        String  sessionId;
        String  error;
    }

    // ── Session management ─────────────────────────────────────────────────────

    private static SessionResult createSession(String token, String baseUrl) {
        SessionResult result = new SessionResult();
        String agentId = getAgentId();
        if (String.isBlank(agentId)) {
            result.error = 'Agent not found for developer name "' + AGENT_DEVELOPER_NAME + '".';
            return result;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(AGENT_API_BASE_URL + '/agents/' + agentId + '/sessions');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);

        String externalKey = EncodingUtil.convertToHex(
            Crypto.generateAesKey(128)
        ).substring(0, 32);

        Map<String, Object> body = new Map<String, Object>{
            'externalSessionKey' => externalKey
        };
        req.setBody(JSON.serialize(body));

        try {
            HttpResponse res = new Http().send(req);
            String respBody = res.getBody();
            Integer status  = res.getStatusCode();

            if (status == 200 || status == 201) {
                Map<String, Object> parsed =
                    (Map<String, Object>) JSON.deserializeUntyped(respBody);
                String sid = (String) parsed.get('sessionId');
                if (sid == null) { sid = (String) parsed.get('id'); }
                if (sid == null) { sid = (String) parsed.get('session_id'); }
                if (String.isNotBlank(sid)) {
                    result.success   = true;
                    result.sessionId = sid;
                } else {
                    result.error = 'Session created but no sessionId field found. Body: ' + respBody;
                }
            } else {
                result.error = 'HTTP ' + status + ': ' + respBody;
            }
        } catch (Exception e) {
            result.error = 'Callout exception: ' + e.getMessage();
        }
        return result;
    }

    // ── Message sending ────────────────────────────────────────────────────────

    private static String sendMessage(
        String token, String baseUrl, String sessionId, String message
    ) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(AGENT_API_BASE_URL + '/sessions/' + sessionId + '/messages');
        req.setMethod('POST');
        req.setHeader('Accept', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);

        Map<String, Object> msgObj = new Map<String, Object>{
            'sequenceId' => 1,
            'type'       => 'Text',
            'text'       => message
        };
        req.setBody(JSON.serialize(new Map<String, Object>{ 'message' => msgObj }));

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                return extractReply(res.getBody());
            }
            return 'Agent error (' + res.getStatusCode() + '): ' + res.getBody();
        } catch (Exception e) {
            return 'Agent error: ' + e.getMessage();
        }
    }

    // ── Response parsing ───────────────────────────────────────────────────────

    private static String extractReply(String responseBody) {
        try {
            Map<String, Object> parsed =
                (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> messages = (List<Object>) parsed.get('messages');
            if (messages != null && !messages.isEmpty()) {
                for (Integer i = messages.size() - 1; i >= 0; i--) {
                    Map<String, Object> msg = (Map<String, Object>) messages[i];
                    String msgType = (String) msg.get('type');
                    if (msgType == 'Inform' || msgType == 'Text') {
                        Object msgContent = msg.get('message');
                        if (msgContent instanceof String) {
                            return (String) msgContent;
                        }
                        if (msgContent instanceof Map<String, Object>) {
                            Map<String, Object> contentMap = (Map<String, Object>) msgContent;
                            if (contentMap.containsKey('text')) {
                                return (String) contentMap.get('text');
                            }
                        }
                    }
                }
                Map<String, Object> first = (Map<String, Object>) messages[0];
                Object firstContent = first.get('message');
                if (firstContent instanceof String) {
                    return (String) firstContent;
                }
                if (firstContent instanceof Map<String, Object>) {
                    Map<String, Object> contentMap = (Map<String, Object>) firstContent;
                    return (String) contentMap.get('text');
                }
            }
        } catch (Exception e) {
            System.debug('extractReply parse error: ' + e.getMessage());
        }
        return responseBody;
    }

    private static String getAgentId() {
        try {
            List<BotDefinition> agents = [
                SELECT Id
                FROM BotDefinition
                WHERE DeveloperName = :AGENT_DEVELOPER_NAME
                LIMIT 1
            ];
            return agents.isEmpty() ? null : (String) agents[0].Id;
        } catch (Exception e) {
            System.debug('Agent lookup error: ' + e.getMessage());
            return null;
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private static String toJson(String reply, String sessionId) {
        Map<String, String> result = new Map<String, String>{
            'reply'     => reply,
            'sessionId' => sessionId != null ? sessionId : ''
        };
        return JSON.serialize(result);
    }
}
