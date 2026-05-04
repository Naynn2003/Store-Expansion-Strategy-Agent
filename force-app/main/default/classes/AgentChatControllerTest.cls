@IsTest
private class AgentChatControllerTest {

    @IsTest
    static void buildsAgentApiBaseUrlFromMyDomain() {
        System.assertEquals(
            'https://example.my.salesforce.com/einstein/ai-agent/v1',
            AgentChatController.buildAgentApiBaseUrl('https://example.my.salesforce.com/')
        );
    }

    @IsTest
    static void buildsTokenEndpointFromMyDomain() {
        System.assertEquals(
            'https://example.my.salesforce.com/services/oauth2/token',
            AgentChatController.buildTokenEndpoint('https://example.my.salesforce.com/')
        );
    }

    @IsTest
    static void returnsNullForBlankBaseUrl() {
        System.assertEquals(null, AgentChatController.buildAgentApiBaseUrl(null));
        System.assertEquals(null, AgentChatController.buildTokenEndpoint(''));
    }
}
