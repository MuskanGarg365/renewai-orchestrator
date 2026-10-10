/**
 * Agentforce action: Run Decision. Every number comes from the deterministic
 * Apex engine; the agent only reads and explains the result.
 */
public with sharing class RenewAIAgentRunDecision {

    public class Request {
        @InvocableVariable(
            label='Objective Mode'
            description='One of: Balanced, Cost First, Clean Energy First, Reliability First. Use Balanced if the user does not say.'
            required=false
        )
        public String objectiveMode;
        @InvocableVariable(
            label='As Of (UTC)'
            description='Optional UTC timestamp on a 15-minute boundary. Leave blank to use the current demo snapshot.'
            required=false
        )
        public String asOf;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when a decision was produced and saved.')
        public Boolean success;
        @InvocableVariable(label='Correlation ID' description='Audit ID. Always quote it in the reply.')
        public String correlationId;
        @InvocableVariable(label='Decision ID' description='Salesforce ID of the saved decision.')
        public String decisionId;
        @InvocableVariable(label='Snapshot Time (UTC)' description='The snapshot the decision is based on.')
        public String snapshotTime;
        @InvocableVariable(label='Objective Mode' description='The objective that was used.')
        public String objectiveMode;
        @InvocableVariable(label='Selected Action Cluster' description='Name of the action cluster the engine selected.')
        public String selectedLabel;
        @InvocableVariable(label='Setpoints' description='The exact setpoints in MW. Quote these as written. Never change them.')
        public String setpoints;
        @InvocableVariable(label='Approval Status' description='Pending means a human must approve before execution. Not Required means no approval is needed.')
        public String approvalStatus;
        @InvocableVariable(label='Forecast Confidence Percent' description='Forecast confidence, 0 to 100.')
        public Decimal confidencePct;
        @InvocableVariable(label='Reserve Target MW' description='Battery reserve the engine wants to hold.')
        public Decimal reserveMW;
        @InvocableVariable(label='Score' description='Weighted score of the selected cluster. Lower is better.')
        public Decimal score;
        @InvocableVariable(label='Score Breakdown' description='Contribution of each cost term to the score.')
        public String scoreBreakdown;
        @InvocableVariable(label='Rejected Alternatives' description='Alternatives removed by hard safety constraints, with reasons.')
        public String rejectedAlternatives;
        @InvocableVariable(label='Explanation' description='Engine-written explanation of the trade-offs.')
        public String explanation;
        @InvocableVariable(label='Error Code' description='Set only when success is false.')
        public String errorCode;
        @InvocableVariable(label='Error Message' description='Set only when success is false.')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Run Decision'
        description='Runs the deterministic decision engine for a chosen objective and saves the decision. All setpoints come from this action, never from the agent.'
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

        Savepoint savepoint = Database.setSavepoint();
        try {
            RenewAIDTO.DecisionRequest decisionRequest =
                new RenewAIDTO.DecisionRequest();
            decisionRequest.asOf = RenewAIAgentSupport.parseAsOf(
                request == null ? null : request.asOf);
            decisionRequest.objectiveMode =
                request == null ? null : request.objectiveMode;

            RenewAIDTO.DecisionResponse result =
                RenewAIDecisionService.run(
                    decisionRequest, response.correlationId);

            response.success = true;
            response.decisionId = String.valueOf(result.decisionId);
            response.snapshotTime =
                result.asOf.formatGmt('yyyy-MM-dd HH:mm') + ' UTC';
            response.objectiveMode = result.objectiveMode;
            response.selectedLabel = result.selected.label;
            response.setpoints =
                RenewAIAgentSupport.describeActions(result.selected.actions);
            response.approvalStatus = result.approvalStatus;
            response.confidencePct = result.confidence * 100;
            response.reserveMW = result.reserveMW;
            response.score = result.selected.score;
            response.scoreBreakdown =
                RenewAIAgentSupport.describeScore(result.selected.breakdown);
            response.rejectedAlternatives =
                RenewAIAgentSupport.describeRejected(result.rejected);
            response.explanation = result.explanation;
        } catch (Exception exceptionRecord) {
            Database.rollback(savepoint);
            RenewAIAgentSupport.Failure failure =
                RenewAIAgentSupport.toFailure(
                    exceptionRecord, response.correlationId);
            response.success = false;
            response.errorCode = failure.errorCode;
            response.errorMessage = failure.message;
        }
        return response;
    }
}
