/**
 * Agentforce action: Get Decision Explanation. Read-only. Looks up a saved
 * decision by Decision ID or Correlation ID and returns what the engine
 * recorded. It never re-runs or changes anything.
 */
public with sharing class RenewAIAgentGetExplanation {

    public class Request {
        @InvocableVariable(
            label='Decision ID'
            description='Salesforce ID of a saved decision (starts with a0). Use this or the Correlation ID.'
            required=false
        )
        public String decisionId;
        @InvocableVariable(
            label='Correlation ID'
            description='Correlation ID from an earlier Run Decision or Run Scenario result, for example RENEWAI-1A2B3C4D5E6F. Use this or the Decision ID.'
            required=false
        )
        public String correlationId;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when the saved decision was found.')
        public Boolean success;
        @InvocableVariable(label='Correlation ID' description='Audit ID of the decision that was read. Always quote it in the reply.')
        public String correlationId;
        @InvocableVariable(label='Decision ID' description='Salesforce ID of the decision.')
        public String decisionId;
        @InvocableVariable(label='Snapshot Time (UTC)' description='The snapshot the decision was based on.')
        public String snapshotTime;
        @InvocableVariable(label='Objective Mode' description='The objective that was used.')
        public String objectiveMode;
        @InvocableVariable(label='Scenario Phase' description='Baseline or Disturbed when the decision belongs to a scenario, otherwise blank.')
        public String scenarioPhase;
        @InvocableVariable(label='Recommended Action' description='The saved setpoints. Quote as written.')
        public String recommendedAction;
        @InvocableVariable(label='Approval Status' description='Pending means a human must approve before execution.')
        public String approvalStatus;
        @InvocableVariable(label='Confidence Percent' description='Forecast confidence, 0 to 100.')
        public Decimal confidencePct;
        @InvocableVariable(label='Score' description='Weighted score. Lower is better.')
        public Decimal score;
        @InvocableVariable(label='Explanation' description='Engine-written explanation saved with the decision.')
        public String explanation;
        @InvocableVariable(label='Error Code' description='Set only when success is false.')
        public String errorCode;
        @InvocableVariable(label='Error Message' description='Set only when success is false.')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Get Decision Explanation'
        description='Reads a saved decision and its engine-written explanation by Decision ID or Correlation ID. Read-only.'
        category='RenewAI'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request request : requests) {
            responses.add(runOne(request));
        }
        return responses;
    }

    private static Response runOne(Request request) {
        Response response = new Response();
        response.correlationId = RenewAIAgentSupport.newCorrelationId();

        try {
            Decision__c decision = find(request);
            if (decision == null) {
                response.success = false;
                response.errorCode = 'DECISION_NOT_FOUND';
                response.errorMessage =
                    'No saved decision matches that ID. Run a decision first.';
                return response;
            }

            response.success = true;
            response.correlationId = decision.Correlation_Id__c;
            response.decisionId = String.valueOf(decision.Id);
            response.snapshotTime = decision.Snapshot_Time__c == null
                ? ''
                : decision.Snapshot_Time__c.formatGmt('yyyy-MM-dd HH:mm') + ' UTC';
            response.objectiveMode = decision.Objective_Mode__c;
            response.scenarioPhase = decision.Scenario_Phase__c;
            response.recommendedAction = decision.Recommended_Action__c;
            response.approvalStatus = decision.Approval_Status__c;
            response.confidencePct = decision.Confidence__c;
            response.score = decision.Score__c;
            response.explanation = decision.Reasoning__c;
        } catch (Exception exceptionRecord) {
            RenewAIAgentSupport.Failure failure =
                RenewAIAgentSupport.toFailure(
                    exceptionRecord, response.correlationId);
            response.success = false;
            response.errorCode = failure.errorCode;
            response.errorMessage = failure.message;
        }
        return response;
    }

    // A scenario saves a Baseline and a Disturbed decision under one
    // correlation ID. The Disturbed one is returned (Disturbed sorts after
    // Baseline); decisions outside a scenario have a single row.
    private static Decision__c find(Request request) {
        if (request == null ||
            (String.isBlank(request.decisionId) &&
             String.isBlank(request.correlationId))) {
            throw new RenewAIValidationException(
                new List<RenewAIDTO.ErrorDetail>{
                    new RenewAIDTO.ErrorDetail(
                        'decisionId',
                        'REQUIRED',
                        'Provide a Decision ID or a Correlation ID.'
                    )
                }
            );
        }

        List<Decision__c> rows;
        if (!String.isBlank(request.decisionId)) {
            Id parsedId;
            try {
                parsedId = Id.valueOf(request.decisionId.trim());
            } catch (Exception exceptionRecord) {
                throw new RenewAIValidationException(
                    new List<RenewAIDTO.ErrorDetail>{
                        new RenewAIDTO.ErrorDetail(
                            'decisionId',
                            'INVALID_ID',
                            'That is not a valid Decision ID.'
                        )
                    }
                );
            }
            rows = [
                SELECT Id, Correlation_Id__c, Snapshot_Time__c,
                       Objective_Mode__c, Scenario_Phase__c,
                       Recommended_Action__c, Approval_Status__c,
                       Confidence__c, Score__c, Reasoning__c
                FROM Decision__c
                WHERE Id = :parsedId
                WITH USER_MODE
                LIMIT 1
            ];
        } else {
            String correlation = request.correlationId.trim();
            rows = [
                SELECT Id, Correlation_Id__c, Snapshot_Time__c,
                       Objective_Mode__c, Scenario_Phase__c,
                       Recommended_Action__c, Approval_Status__c,
                       Confidence__c, Score__c, Reasoning__c
                FROM Decision__c
                WHERE Correlation_Id__c = :correlation
                WITH USER_MODE
                ORDER BY Scenario_Phase__c DESC NULLS LAST, CreatedDate DESC
                LIMIT 1
            ];
        }
        return rows.isEmpty() ? null : rows[0];
    }
}
