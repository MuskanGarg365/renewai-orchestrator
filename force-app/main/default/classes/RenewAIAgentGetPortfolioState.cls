/**
 * Agentforce action: Get Portfolio State. Read-only. Returns the same
 * portfolio the dashboard shows, as flat fields the agent can quote.
 */
public with sharing class RenewAIAgentGetPortfolioState {

    public class Request {
        @InvocableVariable(
            label='As Of (UTC)'
            description='Optional UTC timestamp on a 15-minute boundary, for example 2026-10-09T06:30:00Z. Leave blank to use the current demo snapshot.'
            required=false
        )
        public String asOf;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when the portfolio was read.')
        public Boolean success;
        @InvocableVariable(label='Correlation ID' description='Audit ID. Always quote it in the reply.')
        public String correlationId;
        @InvocableVariable(label='Snapshot Time (UTC)' description='The snapshot the numbers are from.')
        public String snapshotTime;
        @InvocableVariable(label='Renewable Output MW' description='Total solar and wind output in MW.')
        public Decimal renewableMW;
        @InvocableVariable(label='Solar Output MW' description='Solar output in MW.')
        public Decimal solarMW;
        @InvocableVariable(label='Demand MW' description='Total industrial demand in MW.')
        public Decimal demandMW;
        @InvocableVariable(label='Demand Gap MW' description='Demand minus renewable output. Positive means a shortfall.')
        public Decimal demandGapMW;
        @InvocableVariable(label='Energy Price INR per MWh' description='Latest market price.')
        public Decimal energyPriceMWh;
        @InvocableVariable(label='Forecast Confidence Percent' description='Forecast confidence from weather scores, 0 to 100.')
        public Decimal confidencePct;
        @InvocableVariable(label='Battery Status' description='State of charge and availability of each battery.')
        public String batteryStatus;
        @InvocableVariable(label='Summary' description='One-paragraph plain-language summary.')
        public String summary;
        @InvocableVariable(label='Error Code' description='Set only when success is false.')
        public String errorCode;
        @InvocableVariable(label='Error Message' description='Set only when success is false.')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Get Portfolio State'
        description='Reads the current renewable output, demand, price, forecast confidence and battery state. Read-only. Use this before explaining anything about the portfolio.'
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
            Datetime asOf = RenewAIAgentSupport.parseAsOf(
                request == null ? null : request.asOf);
            RenewAIDecisionEngine.Context ctx =
                RenewAIDecisionService.loadContext(asOf, response.correlationId);

            List<String> batteries = new List<String>();
            for (RenewAIDecisionEngine.Battery b : ctx.batteries) {
                batteries.add(
                    b.assetCode + ' ' + RenewAIAgentSupport.num(b.socPercent) +
                    '% charged, ' + (b.available ? 'online' : 'offline')
                );
            }

            response.success = true;
            response.snapshotTime = asOf.formatGmt('yyyy-MM-dd HH:mm') + ' UTC';
            response.renewableMW = ctx.renewableMW;
            response.solarMW = ctx.solarMW;
            response.demandMW = ctx.demandMW;
            response.demandGapMW = ctx.demandMW - ctx.renewableMW;
            response.energyPriceMWh = ctx.priceMWh;
            response.confidencePct = ctx.confidence * 100;
            response.batteryStatus = String.join(batteries, '; ');
            response.summary =
                'At ' + response.snapshotTime + ', renewables produce ' +
                RenewAIAgentSupport.num(ctx.renewableMW) + ' MW against demand of ' +
                RenewAIAgentSupport.num(ctx.demandMW) + ' MW (gap ' +
                RenewAIAgentSupport.num(response.demandGapMW) +
                ' MW). Price is ' + RenewAIAgentSupport.num(ctx.priceMWh) +
                ' INR/MWh and forecast confidence is ' +
                RenewAIAgentSupport.num(response.confidencePct) + '%. Batteries: ' +
                response.batteryStatus + '.';
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
