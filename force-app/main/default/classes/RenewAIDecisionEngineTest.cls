@IsTest
private class RenewAIDecisionEngineTest {

    // Baseline mirrors the seeded 12:00 IST (06:30Z) portfolio.
    private static RenewAIDecisionEngine.Context baseline() {
        return context(160.24, 161.21, 80, 72, true, 0.85);
    }

    private static RenewAIDecisionEngine.Context context(
        Decimal renewable,
        Decimal demand,
        Decimal soc1,
        Decimal soc2,
        Boolean available,
        Decimal confidence
    ) {
        RenewAIDecisionEngine.Context ctx =
            new RenewAIDecisionEngine.Context();
        ctx.asOf = Datetime.newInstanceGmt(2026, 10, 9, 6, 30, 0);
        ctx.renewableMW = renewable;
        ctx.demandMW = demand;
        ctx.priceMWh = 3050;
        ctx.gridLimitMW = 150;
        ctx.confidence = confidence;
        ctx.gridAssetCode = 'GRID_INDIA_01';
        ctx.batteries.add(new RenewAIDecisionEngine.Battery(
            'BATTERY_MH_01', 20, soc1, available));
        ctx.batteries.add(new RenewAIDecisionEngine.Battery(
            'BATTERY_MH_02', 20, soc2, available));
        return ctx;
    }

    private static Decimal quantityOf(
        RenewAIDTO.CandidateResult candidate,
        String actionType
    ) {
        Decimal total = 0;
        for (RenewAIDTO.ActionLine line : candidate.actions) {
            if (line.actionType == actionType) {
                total += line.quantityMW;
            }
        }
        return total;
    }

    private static Boolean hasReason(
        RenewAIDecisionEngine.EngineResult result,
        String candidateId,
        String reason
    ) {
        for (RenewAIDTO.CandidateResult r : result.rejected) {
            if (r.candidateId == candidateId &&
                r.rejectionReasons.contains(reason)) {
                return true;
            }
        }
        return false;
    }

    @IsTest
    static void baselineIsDeterministic() {
        RenewAIDecisionEngine.EngineResult first =
            RenewAIDecisionEngine.decide(baseline(), 'Balanced');
        RenewAIDecisionEngine.EngineResult second =
            RenewAIDecisionEngine.decide(baseline(), 'Balanced');

        System.assertEquals('RESERVE_DISCHARGE', first.selected.candidateId);
        System.assertEquals(first.selected.candidateId, second.selected.candidateId);
        System.assertEquals(first.selected.score, second.selected.score);
        System.assertEquals('Not Required', first.approvalStatus);
        assertClose(7.25, first.reserveMW, 0.01, 'reserve target');
        assertClose(0.1524, first.selected.score, 0.002, 'golden Balanced score');
    }

    @IsTest
    static void selectedActionsKeepThePowerBalance() {
        for (String mode : new List<String>{
            'Balanced', 'Cost First', 'Clean Energy First', 'Reliability First'
        }) {
            RenewAIDecisionEngine.Context ctx = baseline();
            RenewAIDecisionEngine.EngineResult result =
                RenewAIDecisionEngine.decide(ctx, mode);
            RenewAIDTO.CandidateResult s = result.selected;

            Decimal balance = ctx.renewableMW
                - quantityOf(s, 'Curtail')
                + quantityOf(s, 'Discharge')
                + quantityOf(s, 'Buy')
                - quantityOf(s, 'Charge')
                - quantityOf(s, 'Sell')
                - ctx.demandMW;

            System.assert(
                Math.abs(balance) <= 0.5,
                mode + ' selected an unbalanced cluster: ' + balance);
            System.assertEquals(true, s.feasible);
        }
    }

    @IsTest
    static void objectiveModeChangesTheWinner() {
        RenewAIDecisionEngine.EngineResult balanced =
            RenewAIDecisionEngine.decide(baseline(), 'Balanced');
        RenewAIDecisionEngine.EngineResult costFirst =
            RenewAIDecisionEngine.decide(baseline(), 'Cost First');

        System.assertEquals('RESERVE_DISCHARGE', balanced.selected.candidateId);
        System.assertEquals('DISCHARGE_AND_SELL', costFirst.selected.candidateId);
        System.assertNotEquals(
            balanced.selected.candidateId, costFirst.selected.candidateId);

        // The aggressive cluster leaves no reserve, so it needs approval.
        System.assertEquals('Pending', costFirst.approvalStatus);
        System.assertEquals(6, costFirst.selected.breakdown.size());
    }

    @IsTest
    static void lowSocNeverDischargesBelowTheMinimum() {
        RenewAIDecisionEngine.Context ctx =
            context(160.24, 161.21, 12, 4, true, 0.85);
        RenewAIDecisionEngine.EngineResult result =
            RenewAIDecisionEngine.decide(ctx, 'Cost First');

        System.assertEquals(true,
            hasReason(result, 'DISCHARGE_AND_SELL', 'SOC_MIN_VIOLATION'));

        // 12% SOC on a 40 MWh battery supports at most 3.2 MW for 15 minutes.
        System.assert(
            quantityOf(result.selected, 'Discharge') <= 3.2 + 0.5,
            'Selected discharge exceeds what the SOC allows');
    }

    @IsTest
    static void unavailableBatteryIsNeverUsed() {
        RenewAIDecisionEngine.Context ctx =
            context(160.24, 161.21, 80, 72, false, 0.85);

        for (String mode : new List<String>{'Balanced', 'Cost First'}) {
            RenewAIDecisionEngine.EngineResult result =
                RenewAIDecisionEngine.decide(ctx, mode);

            System.assertEquals('GRID_BALANCE', result.selected.candidateId);
            assertClose(0, quantityOf(result.selected, 'Discharge'), 0.01, 'discharge');
            assertClose(0, quantityOf(result.selected, 'Charge'), 0.01, 'charge');
            assertClose(0, quantityOf(result.selected, 'Reserve'), 0.01, 'reserve');
            System.assertEquals(true,
                hasReason(result, 'DISCHARGE_AND_SELL', 'BATTERY_UNAVAILABLE'));
            System.assertEquals('Pending', result.approvalStatus);
        }
    }

    @IsTest
    static void lowConfidenceRaisesReserveAndRequiresApproval() {
        RenewAIDecisionEngine.EngineResult result =
            RenewAIDecisionEngine.decide(
                context(160.24, 161.21, 80, 72, true, 0.4), 'Balanced');

        assertClose(14, result.reserveMW, 0.01, 'reserve target');
        System.assertEquals('Pending', result.approvalStatus);
        assertClose(14, quantityOf(result.selected, 'Reserve'), 0.01, 'reserve held');
    }

    @IsTest
    static void surplusIsSoldOrStoredNotWasted() {
        RenewAIDecisionEngine.EngineResult result =
            RenewAIDecisionEngine.decide(
                context(180, 160, 80, 72, true, 0.85), 'Balanced');

        assertClose(0, quantityOf(result.selected, 'Buy'), 0.01, 'buy');
        assertClose(0, quantityOf(result.selected, 'Curtail'), 0.01, 'curtail');
        assertClose(20, quantityOf(result.selected, 'Sell')
            + quantityOf(result.selected, 'Charge'), 0.01, 'surplus used');
    }

    @IsTest
    static void invalidModeIsRejected() {
        try {
            RenewAIDecisionEngine.decide(baseline(), 'Fastest');
            System.assert(false, 'Expected a validation exception');
        } catch (RenewAIValidationException e) {
            System.assertEquals('INVALID_MODE', e.validationErrors[0].code);
        }
    }

    @IsTest
    static void missingPriceIsRejected() {
        RenewAIDecisionEngine.Context ctx = baseline();
        ctx.priceMWh = null;
        try {
            RenewAIDecisionEngine.decide(ctx, 'Balanced');
            System.assert(false, 'Expected a validation exception');
        } catch (RenewAIValidationException e) {
            System.assertEquals('MISSING_PRICE', e.validationErrors[0].code);
        }
    }

    private static void assertClose(
        Decimal expected,
        Decimal actual,
        Decimal tolerance,
        String message
    ) {
        System.assert(
            actual != null && Math.abs(expected - actual) <= tolerance,
            message + ': expected ' + expected + ' but got ' + actual
        );
    }
}
