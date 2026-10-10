/**
 * Agentforce action: Run Scenario. Applies one of the four scripted
 * disturbances and returns the before/after decisions from the engine.
 */
public with sharing class RenewAIAgentRunScenario {

    public class Request {
        @InvocableVariable(
            label='Scenario Type'
            description='One of: Cloud Front, Price Spike, Demand Surge, Battery Outage.'
            required=true
        )
        public String scenarioType;
        @InvocableVariable(
            label='Objective Mode'
            description='Optional. One of: Balanced, Cost First, Clean Energy First, Reliability First. Leave blank to use the scenario default.'
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
        @InvocableVariable(label='Success' description='True when the scenario completed and was saved.')
        public Boolean success;
        @InvocableVariable(label='Correlation ID' description='Audit ID. Always quote it in the reply.')
        public String correlationId;
        @InvocableVariable(label='Scenario ID' description='Salesforce ID of the saved scenario.')
        public String scenarioId;
        @InvocableVariable(label='Scenario Type' description='The scenario that was applied.')
        public String scenarioType;
        @InvocableVariable(label='Objective Mode' description='The objective that was used.')
        public String objectiveMode;
        @InvocableVariable(label='Applied Changes' description='What the disturbance changed, as before to after.')
        public String appliedChanges;
        @InvocableVariable(label='Baseline Cluster' description='Action cluster before the disturbance.')
        public String baselineLabel;
        @InvocableVariable(label='Baseline Setpoints' description='Exact setpoints before the disturbance.')
        public String baselineSetpoints;
        @InvocableVariable(label='Disturbed Cluster' description='Action cluster after the disturbance.')
        public String disturbedLabel;
        @InvocableVariable(label='Disturbed Setpoints' description='Exact setpoints after the disturbance. Quote these as written. Never change them.')
        public String disturbedSetpoints;
        @InvocableVariable(label='Decision Changed' description='True if the engine chose a different action cluster after the disturbance.')
        public Boolean decisionChanged;
        @InvocableVariable(label='Approval Status After' description='Pending means a human must approve before execution.')
        public String approvalStatus;
        @InvocableVariable(label='Key Changes' description='The metrics that moved, with before, after and change.')
        public String keyChanges;
        @InvocableVariable(label='Explanation After' description='Engine-written explanation of the new decision.')
        public String explanation;
        @InvocableVariable(label='Error Code' description='Set only when success is false.')
        public String errorCode;
        @InvocableVariable(label='Error Message' description='Set only when success is false.')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Run Scenario'
        description='Applies a scripted disturbance (Cloud Front, Price Spike, Demand Surge or Battery Outage), re-runs the deterministic engine and returns the before and after decisions. All setpoints come from this action.'
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
            RenewAIDTO.ScenarioRequest scenarioRequest =
                new RenewAIDTO.ScenarioRequest();
            scenarioRequest.asOf = RenewAIAgentSupport.parseAsOf(
                request == null ? null : request.asOf);
            scenarioRequest.scenarioType =
                request == null ? null : request.scenarioType;
            scenarioRequest.objectiveMode =
                request == null ? null : request.objectiveMode;

            // RenewAIScenarioService rolls back its own saves on failure.
            RenewAIDTO.ScenarioResponse result =
                RenewAIScenarioService.run(
                    scenarioRequest, response.correlationId);

            List<String> params = new List<String>();
            for (RenewAIDTO.ParamChange p : result.parameters) {
                params.add(p.name + ' ' + p.before + ' to ' + p.after);
            }

            List<String> moved = new List<String>();
            for (RenewAIDTO.MetricDelta d : result.comparison.deltas) {
                if (d.change != 0) {
                    moved.add(
                        d.label + ' ' + RenewAIAgentSupport.num(d.baseline) +
                        ' to ' + RenewAIAgentSupport.num(d.disturbed) + ' ' +
                        d.unit
                    );
                }
            }

            response.success = true;
            response.scenarioId = String.valueOf(result.scenarioId);
            response.scenarioType = result.scenarioType;
            response.objectiveMode = result.objectiveMode;
            response.appliedChanges = String.join(params, '; ');
            response.baselineLabel = result.baseline.selected.label;
            response.baselineSetpoints = RenewAIAgentSupport.describeActions(
                result.baseline.selected.actions);
            response.disturbedLabel = result.disturbed.selected.label;
            response.disturbedSetpoints = RenewAIAgentSupport.describeActions(
                result.disturbed.selected.actions);
            response.decisionChanged = result.comparison.decisionChanged;
            response.approvalStatus = result.disturbed.approvalStatus;
            response.keyChanges = String.join(moved, '; ');
            response.explanation = result.disturbed.explanation;
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
}
