@IsTest
private class RenewAISimulationEngineTest {

    private static final List<String> MODES = new List<String>{
        'Balanced', 'Cost First', 'Clean Energy First', 'Reliability First'
    };

    // The eight base intervals of the seeded day, 12:00 to 13:45 IST
    // (06:30Z to 08:15Z). Fixed numbers, so this is the deterministic fixture.
    private static final List<List<Decimal>> BASE = new List<List<Decimal>>{
        // renewable, solar, demand, price, soc1, soc2
        new List<Decimal>{ 160.24, 126.90, 161.21, 3050.00, 80.00, 72.00 },
        new List<Decimal>{ 159.77, 126.63, 162.56, 3101.94, 79.95, 71.95 },
        new List<Decimal>{ 158.78, 125.82, 163.80, 3155.58, 79.79, 71.79 },
        new List<Decimal>{ 157.28, 124.46, 164.94, 3210.70, 79.52, 71.52 },
        new List<Decimal>{ 155.29, 122.58, 165.98, 3267.06, 79.15, 71.15 },
        new List<Decimal>{ 152.79, 120.17, 166.91, 3324.42, 78.67, 70.67 },
        new List<Decimal>{ 149.80, 117.24, 167.72, 3382.53, 78.10, 70.10 },
        new List<Decimal>{ 146.37, 113.82, 168.41, 3441.14, 77.42, 69.42 }
    };

    private static List<RenewAIDecisionEngine.Context> baseContexts() {
        List<RenewAIDecisionEngine.Context> contexts =
            new List<RenewAIDecisionEngine.Context>();
        Datetime start = Datetime.newInstanceGmt(2026, 10, 9, 6, 30, 0);

        for (Integer i = 0; i < BASE.size(); i++) {
            List<Decimal> row = BASE[i];
            RenewAIDecisionEngine.Context ctx =
                new RenewAIDecisionEngine.Context();
            ctx.asOf = start.addMinutes(15 * i);
            ctx.renewableMW = row[0];
            ctx.solarMW = row[1];
            ctx.demandMW = row[2];
            ctx.priceMWh = row[3];
            ctx.gridLimitMW = 150;
            ctx.confidence = 0.85;
            ctx.gridAssetCode = 'GRID_INDIA_01';
            ctx.batteries.add(new RenewAIDecisionEngine.Battery(
                'BATTERY_MH_01', 20, row[4], true));
            ctx.batteries.add(new RenewAIDecisionEngine.Battery(
                'BATTERY_MH_02', 20, row[5], true));
            contexts.add(ctx);
        }
        return contexts;
    }

    private static RenewAISimulationEngine.Outcome simulate(
        String scenarioType, String mode
    ) {
        return RenewAISimulationEngine.simulate(
            baseContexts(), scenarioType, mode);
    }

    private static void assertClose(
        Decimal expected, Decimal actual, Decimal tolerance, String message
    ) {
        System.assert(
            actual != null && Math.abs(expected - actual) <= tolerance,
            message + ': expected ' + expected + ' but got ' + actual
        );
    }

    private static Set<String> clustersOf(RenewAISimulationEngine.Outcome o) {
        Set<String> ids = new Set<String>();
        for (RenewAIDTO.SimStep s : o.run.steps) {
            ids.add(s.clusterId);
        }
        return ids;
    }

    // ------------------------------------------------- repeatability

    @IsTest
    static void sameInputsGiveTheSameResult() {
        RenewAISimulationEngine.Outcome first =
            simulate('Cloud Front', 'Balanced');
        RenewAISimulationEngine.Outcome second =
            simulate('Cloud Front', 'Balanced');

        System.assertEquals(first.run.checksum, second.run.checksum);
        System.assertEquals(
            first.run.totals.energyCostINR, second.run.totals.energyCostINR);
        System.assertEquals(
            first.run.totals.carbonT, second.run.totals.carbonT);
        System.assertEquals(8, first.run.steps.size());
    }

    @IsTest
    static void differentObjectivesGiveDifferentChecksums() {
        System.assertNotEquals(
            simulate('Cloud Front', 'Balanced').run.checksum,
            simulate('Cloud Front', 'Cost First').run.checksum);
    }

    // ---------------------------------------------------- golden fixtures

    @IsTest
    static void cloudFrontBalancedGolden() {
        RenewAISimulationEngine.Outcome o = simulate('Cloud Front', 'Balanced');
        RenewAIDTO.SimTotals t = o.run.totals;

        System.assertEquals('RESERVE_DISCHARGE', o.run.steps[0].clusterId);
        System.assertEquals('HOLD_AND_RESERVE', o.run.steps[3].clusterId);
        System.assertEquals('RESERVE_DISCHARGE', o.run.steps[7].clusterId);
        assertClose(190632, t.energyCostINR, 2000, 'energy cost');
        assertClose(45.25, t.carbonT, 0.6, 'carbon');
        System.assertEquals(0, t.revenueINR);
        System.assertEquals(0, t.reliabilityEvents);
        System.assertEquals(3, t.pendingApprovals);
        System.assertEquals(2, t.clusterChanges);
    }

    @IsTest
    static void priceSpikeCostFirstGolden() {
        RenewAISimulationEngine.Outcome o = simulate('Price Spike', 'Cost First');
        RenewAIDTO.SimTotals t = o.run.totals;

        assertClose(147263, t.revenueINR, 2200, 'revenue');
        assertClose(4.52, t.carbonT, 0.2, 'carbon');
        System.assertEquals(4, t.reliabilityEvents);
        System.assertEquals(4, t.pendingApprovals);
        System.assertEquals('DISCHARGE_AND_SELL', o.run.steps[2].clusterId);
        System.assertEquals('HOLD_AND_RESERVE', o.run.steps[7].clusterId);
    }

    @IsTest
    static void demandSurgeBalancedGolden() {
        RenewAISimulationEngine.Outcome o = simulate('Demand Surge', 'Balanced');
        RenewAIDTO.SimTotals t = o.run.totals;

        System.assertEquals(2, t.reliabilityEvents);
        System.assertEquals(2, t.pendingApprovals);
        System.assertEquals(3, t.clusterChanges);
        assertClose(38250, t.energyCostINR, 800, 'energy cost');
    }

    @IsTest
    static void batteryOutageCostFirstGolden() {
        RenewAISimulationEngine.Outcome o =
            simulate('Battery Outage', 'Cost First');

        System.assertEquals(3, o.run.totals.pendingApprovals);
        System.assertEquals('DISCHARGE_AND_SELL', o.run.steps[0].clusterId);
        System.assertEquals('RESERVE_DISCHARGE', o.run.steps[3].clusterId);

        // Unit 1 goes offline from step 3 and is never dispatched again, so
        // its charge level stays frozen.
        System.assertEquals(true, o.run.steps[2].batteries[0].available);
        for (Integer i = 3; i < 8; i++) {
            System.assertEquals(false, o.run.steps[i].batteries[0].available);
            assertClose(
                o.run.steps[3].batteries[0].socPercent,
                o.run.steps[i].batteries[0].socPercent,
                0.01, 'offline battery charge at step ' + i);
        }
    }

    // ------------------------------------------------ behaviour over time

    @IsTest
    static void actionsChangeAcrossTheTwoHours() {
        for (String scenarioType : RenewAIScenarioCatalog.types()) {
            RenewAISimulationEngine.Outcome o = simulate(
                scenarioType,
                RenewAIScenarioCatalog.defaultModeFor(scenarioType));
            System.assert(
                clustersOf(o).size() >= 2,
                scenarioType + ' should change the action cluster');
        }
    }

    @IsTest
    static void batteryChargeCarriesOverAndNeverLeavesTheLimits() {
        RenewAISimulationEngine.Outcome o = simulate('Cloud Front', 'Balanced');

        for (Integer i = 0; i < 8; i++) {
            for (RenewAIDTO.BatteryPoint b : o.run.steps[i].batteries) {
                System.assert(
                    b.socPercent >= RenewAIDecisionEngine.MIN_SOC - 0.01 &&
                    b.socPercent <= RenewAIDecisionEngine.MAX_SOC + 0.01,
                    'SOC out of range at step ' + i + ': ' + b.socPercent);
            }
            if (i > 0) {
                // Cloud Front only discharges, so charge never rises.
                System.assert(
                    o.run.steps[i].batteries[0].socPercent <=
                        o.run.steps[i - 1].batteries[0].socPercent + 0.01,
                    'charge should not rise at step ' + i);
            }
        }
        // The step-0 result reflects the 1 MW discharge from the seeded 80%.
        System.assert(o.run.steps[0].batteries[0].socPercent < 80);
    }

    @IsTest
    static void cumulativeKpisAddUp() {
        RenewAISimulationEngine.Outcome o =
            simulate('Price Spike', 'Cost First');
        Decimal cost = 0;
        Decimal revenue = 0;
        Decimal carbon = 0;

        for (Integer i = 0; i < 8; i++) {
            RenewAIDTO.SimStep s = o.run.steps[i];
            cost += s.energyCostINR;
            revenue += s.revenueINR;
            carbon += s.carbonT;
            assertClose(cost, s.cumEnergyCostINR, 0.05, 'cumulative cost');
            assertClose(revenue, s.cumRevenueINR, 0.05, 'cumulative revenue');
            assertClose(carbon, s.cumCarbonT, 0.05, 'cumulative carbon');
        }
        assertClose(cost, o.run.totals.energyCostINR, 0.1, 'total cost');
        assertClose(
            o.run.totals.energyCostINR - o.run.totals.revenueINR,
            o.run.totals.netCostINR, 0.05, 'net cost');
    }

    // ------------------------------------------------------- regression

    @IsTest
    static void everyScenarioAndObjectiveStaysFeasibleAndBalanced() {
        for (String scenarioType : RenewAIScenarioCatalog.types()) {
            for (String mode : MODES) {
                RenewAISimulationEngine.Outcome o =
                    simulate(scenarioType, mode);
                String label = scenarioType + ' / ' + mode;

                for (Integer i = 0; i < 8; i++) {
                    RenewAIDecisionEngine.Context ctx = o.contexts[i];
                    RenewAIDTO.CandidateResult sel = o.results[i].selected;
                    System.assertEquals(true, sel.feasible, label + ' step ' + i);

                    RenewAIDTO.SimStep s = o.run.steps[i];
                    Decimal balance = ctx.renewableMW - s.curtailMW +
                        s.dischargeMW + s.buyMW - s.chargeMW - s.sellMW -
                        ctx.demandMW;
                    System.assert(
                        Math.abs(balance) <= 0.7,
                        label + ' step ' + i + ' unbalanced by ' + balance);
                }
            }
        }
    }

    @IsTest
    static void aSimulationNeedsEightIntervals() {
        List<RenewAIDecisionEngine.Context> five =
            new List<RenewAIDecisionEngine.Context>();
        for (Integer i = 0; i < 5; i++) {
            five.add(baseContexts()[i]);
        }
        try {
            RenewAISimulationEngine.simulate(five, 'Cloud Front', 'Balanced');
            System.assert(false, 'Expected a validation exception');
        } catch (RenewAIValidationException e) {
            System.assertEquals('INVALID_STEPS', e.validationErrors[0].code);
        }
    }

    @IsTest
    static void profilesHaveEightSteps() {
        for (String scenarioType : RenewAIScenarioCatalog.types()) {
            System.assertEquals(
                8, RenewAISimulationEngine.profileFor(scenarioType).size());
        }
    }
}
