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
}