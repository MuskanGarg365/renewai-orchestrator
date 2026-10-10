@IsTest
private class RenewAIApprovalRestTest {

    private static RestResponse post(String path, String body) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/renewai/v1' + path;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        RenewAIRestResource.doPost();
        return RestContext.response;
    }

    private static RestResponse get(String path) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/renewai/v1' + path;
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();
        RenewAIRestResource.doGet();
        return RestContext.response;
    }

    private static Map<String, Object> json(RestResponse res) {
        return (Map<String, Object>) JSON.deserializeUntyped(
            res.responseBody.toString());
    }

    @IsTest
    static void nonApproverGets403() {
        RenewAIApprovalService.permissionOverride = false;
        RestResponse res = post(
            '/decision/approval',
            '{"decisionId":"a00000000000001","outcome":"Approved"}');

        System.assertEquals(403, res.statusCode);
        System.assertEquals('APPROVAL_NOT_PERMITTED', json(res).get('errorCode'));
    }

    @IsTest
    static void badOutcomeGets400() {
        RenewAIApprovalService.permissionOverride = true;
        RestResponse res = post(
            '/decision/approval',
            '{"decisionId":"a00000000000001","outcome":"Maybe"}');

        System.assertEquals(400, res.statusCode);
        System.assertEquals('VALIDATION_ERROR', json(res).get('errorCode'));
    }

    @IsTest
    static void approvalWithBrokenJsonGets400() {
        RestResponse res = post('/decision/approval', '{not json');
        System.assertEquals(400, res.statusCode);
        System.assertEquals('INVALID_JSON', json(res).get('errorCode'));
    }

    @IsTest
    static void auditListReturns200() {
        RenewAIApprovalService.permissionOverride = true;
        RestResponse res = get('/decisions?limit=5');

        System.assertEquals(200, res.statusCode);
        Map<String, Object> body = json(res);
        System.assertEquals(true, body.get('success'));
        System.assertEquals(true, body.get('canApprove'));
    }

    @IsTest
    static void auditListRejectsBadStatus() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/renewai/v1/decisions';
        req.httpMethod = 'GET';
        req.addParameter('status', 'Bogus');
        RestContext.request = req;
        RestContext.response = new RestResponse();
        RenewAIRestResource.doGet();

        System.assertEquals(400, RestContext.response.statusCode);
    }
}
