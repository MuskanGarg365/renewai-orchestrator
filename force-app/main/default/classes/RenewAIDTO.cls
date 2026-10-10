public class RenewAIDTO {

    public class PortfolioRequest {
        public Datetime asOf { get; set; }
        public Integer intervalMinutes { get; set; }
        public Integer maximumAgeMinutes { get; set; }
    }

    public class AssetSummary {
        public String assetCode { get; set; }
        public String assetName { get; set; }
        public String assetType { get; set; }
        public Decimal capacityMW { get; set; }
        public Decimal generationMW { get; set; }
        public Decimal demandMW { get; set; }
        public Decimal stateOfChargePercent { get; set; }
        public Decimal availableEnergyMWh { get; set; }
        public Datetime snapshotTimestamp { get; set; }
        public String status { get; set; }
        public Boolean stale { get; set; }
    }

    public class PortfolioMetrics {
        public Decimal renewableTotalMW { get; set; }
        public Decimal totalDemandMW { get; set; }
        public Decimal demandGapMW { get; set; }
        public Decimal availableBatteryEnergyMWh { get; set; }
        public Decimal gridCapacityMW { get; set; }
        public Decimal gridHeadroomMW { get; set; }
        public Decimal energyPriceMWh { get; set; }
        public Datetime priceTimestamp { get; set; }
    }

    public class PortfolioResponse {
        public Boolean success { get; set; }
        public String correlationId { get; set; }
        public Datetime asOf { get; set; }
        public Integer intervalMinutes { get; set; }
        public PortfolioMetrics metrics { get; set; }
        public List<AssetSummary> assets { get; set; }

        public PortfolioResponse() {
            success = true;
            assets = new List<AssetSummary>();
        }
    }

    public class AssetsResponse {
        public Boolean success { get; set; }
        public String correlationId { get; set; }
        public List<AssetSummary> assets { get; set; }

        public AssetsResponse() {
            success = true;
            assets = new List<AssetSummary>();
        }
    }

    public class ErrorDetail {
        public String field { get; set; }
        public String code { get; set; }
        public String message { get; set; }

        public ErrorDetail(String field, String code, String message) {
            this.field = field;
            this.code = code;
            this.message = message;
        }
    }

    public class ErrorResponse {
        public Boolean success { get; set; }
        public String correlationId { get; set; }
        public String errorCode { get; set; }
        public String message { get; set; }
        public List<ErrorDetail> errors { get; set; }

        public ErrorResponse() {
            success = false;
            errors = new List<ErrorDetail>();
        }
    }

    // ---------------- Day 5: decision engine ----------------

    public class DecisionRequest {
        public Datetime asOf { get; set; }
        public String objectiveMode { get; set; }
    }

    public class ActionLine {
        public String actionType { get; set; }
        public String assetCode { get; set; }
        public Decimal quantityMW { get; set; }

        public ActionLine(
            String actionType,
            String assetCode,
            Decimal quantityMW
        ) {
            this.actionType = actionType;
            this.assetCode = assetCode;
            this.quantityMW = quantityMW;
        }
    }

    public class TermScore {
        public String term { get; set; }
        public Decimal rawValue { get; set; }
        public Decimal normalized { get; set; }
        public Decimal weight { get; set; }
        public Decimal contribution { get; set; }
    }

    public class CandidateResult {
        public String candidateId { get; set; }
        public String label { get; set; }
        public Boolean feasible { get; set; }
        public Decimal score { get; set; }
        public Integer rank { get; set; }
        public List<ActionLine> actions { get; set; }
        public List<String> rejectionReasons { get; set; }
        public List<TermScore> breakdown { get; set; }

        public CandidateResult() {
            actions = new List<ActionLine>();
            rejectionReasons = new List<String>();
            breakdown = new List<TermScore>();
        }
    }

    public class DecisionInputs {
        public Decimal renewableMW { get; set; }
        public Decimal demandMW { get; set; }
        public Decimal demandGapMW { get; set; }
        public Decimal energyPriceMWh { get; set; }
    }

    public class DecisionResponse {
        public Boolean success { get; set; }
        public String correlationId { get; set; }
        public Id decisionId { get; set; }
        public Datetime asOf { get; set; }
        public String objectiveMode { get; set; }
        public Decimal confidence { get; set; }
        public Decimal reserveMW { get; set; }
        public String approvalStatus { get; set; }
        public String explanation { get; set; }
        public DecisionInputs inputs { get; set; }
        public CandidateResult selected { get; set; }
        public List<CandidateResult> alternatives { get; set; }
        public List<CandidateResult> rejected { get; set; }

        public DecisionResponse() {
            success = true;
            alternatives = new List<CandidateResult>();
            rejected = new List<CandidateResult>();
        }
    }

    // ---------------- Day 6: scenarios ----------------

    public class ScenarioRequest {
        public Datetime asOf { get; set; }
        public String scenarioType { get; set; }
        public String objectiveMode { get; set; }
    }

    public class ParamChange {
        public String name { get; set; }
        public String before { get; set; }
        public String after { get; set; }

        public ParamChange(String name, String before, String after) {
            this.name = name;
            this.before = before;
            this.after = after;
        }
    }

    public class MetricDelta {
        public String metric { get; set; }
        public String label { get; set; }
        public String unit { get; set; }
        public Decimal baseline { get; set; }
        public Decimal disturbed { get; set; }
        public Decimal change { get; set; }
    }

    public class ScenarioComparison {
        public Boolean decisionChanged { get; set; }
        public String baselineLabel { get; set; }
        public String disturbedLabel { get; set; }
        public List<MetricDelta> deltas { get; set; }

        public ScenarioComparison() {
            deltas = new List<MetricDelta>();
        }
    }

    public class ScenarioResponse {
        public Boolean success { get; set; }
        public String correlationId { get; set; }
        public Id scenarioId { get; set; }
        public String scenarioType { get; set; }
        public String description { get; set; }
        public String objectiveMode { get; set; }
        public Datetime asOf { get; set; }
        public String status { get; set; }
        public List<ParamChange> parameters { get; set; }
        public DecisionResponse baseline { get; set; }
        public DecisionResponse disturbed { get; set; }
        public ScenarioComparison comparison { get; set; }

        public ScenarioResponse() {
            success = true;
            parameters = new List<ParamChange>();
        }
    }
}
