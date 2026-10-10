/**
 * The four scripted disturbances. Pure logic (no SOQL / DML): takes an engine
 * Context and returns a changed copy plus a list of what changed.
 *
 * intensity is 0..1 and scales each disturbance. Day 6 always uses 1.0;
 * Day 8 ramps it across the eight intervals of a simulation.
 */
public with sharing class RenewAIScenarioCatalog {

    public static final String CLOUD_FRONT = 'Cloud Front';
    public static final String PRICE_SPIKE = 'Price Spike';
    public static final String DEMAND_SURGE = 'Demand Surge';
    public static final String BATTERY_OUTAGE = 'Battery Outage';

    public static final Decimal CLOUD_SOLAR_DROP = 0.40;
    public static final Decimal CLOUD_CONFIDENCE_DROP = 0.30;
    public static final Decimal CONFIDENCE_FLOOR = 0.10;
    public static final Decimal PRICE_SPIKE_RISE = 0.80;
    public static final Decimal DEMAND_SURGE_RISE = 0.15;

    public class Disturbed {
        public RenewAIDecisionEngine.Context context;
        public List<RenewAIDTO.ParamChange> changes =
            new List<RenewAIDTO.ParamChange>();
    }

    public static List<String> types() {
        return new List<String>{
            CLOUD_FRONT, PRICE_SPIKE, DEMAND_SURGE, BATTERY_OUTAGE
        };
    }

    public static Boolean isSupported(String scenarioType) {
        return scenarioType != null && types().contains(scenarioType);
    }

    // Objective that shows the scenario most clearly in a demo.
    public static String defaultModeFor(String scenarioType) {
        if (scenarioType == PRICE_SPIKE || scenarioType == BATTERY_OUTAGE) {
            return 'Cost First';
        }
        return 'Balanced';
    }

    public static String descriptionFor(String scenarioType) {
        switch on scenarioType {
            when 'Cloud Front' {
                return 'A cloud front cuts solar output by 40% and lowers forecast confidence by 0.30.';
            }
            when 'Price Spike' {
                return 'The energy price rises by 80%.';
            }
            when 'Demand Surge' {
                return 'Industrial demand rises 15% above forecast.';
            }
            when 'Battery Outage' {
                return 'The first available battery unit trips offline.';
            }
            when else {
                return '';
            }
        }
    }

    public static RenewAIDecisionEngine.Context copyOf(
        RenewAIDecisionEngine.Context source
    ) {
        RenewAIDecisionEngine.Context copy =
            new RenewAIDecisionEngine.Context();
        copy.asOf = source.asOf;
        copy.renewableMW = source.renewableMW;
        copy.solarMW = source.solarMW;
        copy.demandMW = source.demandMW;
        copy.priceMWh = source.priceMWh;
        copy.gridLimitMW = source.gridLimitMW;
        copy.confidence = source.confidence;
        copy.gridAssetCode = source.gridAssetCode;

        for (RenewAIDecisionEngine.Battery b : source.batteries) {
            copy.batteries.add(new RenewAIDecisionEngine.Battery(
                b.assetCode, b.ratedMW, b.socPercent, b.available));
        }
        return copy;
    }

    public static Disturbed apply(
        RenewAIDecisionEngine.Context base,
        String scenarioType,
        Decimal intensity
    ) {
        if (!isSupported(scenarioType)) {
            throw new RenewAIValidationException(
                new List<RenewAIDTO.ErrorDetail>{
                    new RenewAIDTO.ErrorDetail(
                        'scenarioType',
                        'INVALID_SCENARIO',
                        'Use Cloud Front, Price Spike, Demand Surge or Battery Outage.'
                    )
                }
            );
        }

        Decimal level = Math.min(Math.max(intensity, 0), 1);

        Disturbed result = new Disturbed();
        result.context = copyOf(base);
        RenewAIDecisionEngine.Context ctx = result.context;

        switch on scenarioType {
            when 'Cloud Front' {
                Decimal solarLoss = base.solarMW * CLOUD_SOLAR_DROP * level;
                ctx.renewableMW = base.renewableMW - solarLoss;
                ctx.solarMW = base.solarMW - solarLoss;
                ctx.confidence = Math.max(
                    base.confidence - CLOUD_CONFIDENCE_DROP * level,
                    CONFIDENCE_FLOOR
                );
                result.changes.add(change(
                    'Solar output (MW)', base.solarMW, ctx.solarMW));
                result.changes.add(change(
                    'Renewable total (MW)', base.renewableMW, ctx.renewableMW));
                result.changes.add(change(
                    'Forecast confidence', base.confidence, ctx.confidence));
            }
            when 'Price Spike' {
                ctx.priceMWh = base.priceMWh * (1 + PRICE_SPIKE_RISE * level);
                result.changes.add(change(
                    'Energy price (INR/MWh)', base.priceMWh, ctx.priceMWh));
            }
            when 'Demand Surge' {
                ctx.demandMW = base.demandMW * (1 + DEMAND_SURGE_RISE * level);
                result.changes.add(change(
                    'Demand (MW)', base.demandMW, ctx.demandMW));
            }
            when 'Battery Outage' {
                if (level > 0) {
                    for (RenewAIDecisionEngine.Battery b : ctx.batteries) {
                        if (b.available == true) {
                            b.available = false;
                            result.changes.add(new RenewAIDTO.ParamChange(
                                b.assetCode + ' availability',
                                'Available',
                                'Offline'
                            ));
                            break;
                        }
                    }
                }
            }
        }

        return result;
    }

    private static RenewAIDTO.ParamChange change(
        String name,
        Decimal before,
        Decimal afterValue
    ) {
        return new RenewAIDTO.ParamChange(
            name,
            before.setScale(2, System.RoundingMode.HALF_UP).toPlainString(),
            afterValue.setScale(2, System.RoundingMode.HALF_UP).toPlainString()
        );
    }
}
