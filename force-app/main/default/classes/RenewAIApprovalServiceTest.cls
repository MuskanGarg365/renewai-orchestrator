@IsTest
private class RenewAIApprovalServiceTest {

    private static Decision__c pendingDecision() {
        Decision__c d = new Decision__c(
            Decision_Key__c = 'TEST-APPR-' + String.valueOf(Crypto.getRandomInteger()),
            Correlation_Id__c = 'TEST-APPR',
            Decision_Type__c = 'Buy Power',
            Objective_Mode__c = 'Cost First',
            Approval_Status__c = 'Pending',
            Confidence__c = 55
        );
        insert d;
        insert new List<Action__c>{
            new Action__c(
                Decision__c = d.Id, Action_Type__c = 'Buy',
                Quantity_MW__c = 10, Status__c = 'Awaiting Approval'),
            new Action__c(
                Decision__c = d.Id, Action_Type__c = 'Reserve',
                Quantity_MW__c = 5, Status__c = 'Awaiting Approval')
        };
        return d;
    }

    private static RenewAIDTO.ApprovalRequest req(
        String decisionId, String outcome, String note
    ) {
        RenewAIDTO.ApprovalRequest r = new RenewAIDTO.ApprovalRequest();
        r.decisionId = decisionId;
        r.outcome = outcome;
        r.note = note;
        return r;
    }

    private static void assertValidation(
        RenewAIDTO.ApprovalRequest r, String expectedCode
    ) {
        RenewAIApprovalService.permissionOverride = true;
        try {
            RenewAIApprovalService.decide(r, 'TEST');
            System.assert(false, 'Expected a validation error');
        } catch (RenewAIValidationException e) {
            System.assertEquals(
                expectedCode, e.validationErrors[0].code);
        }
    }

    @IsTest
    static void approveMovesActionsToPlanned() {
        Decision__c d = pendingDecision();
        RenewAIApprovalService.permissionOverride = true;

        RenewAIDTO.ApprovalResponse out = RenewAIApprovalService.decide(
            req(d.Id, 'Approved', 'Checked with grid desk'), 'TEST-1');

        System.assertEquals('Approved', out.approvalStatus);
        System.assertEquals(2, out.actionsUpdated);

        Decision__c saved = [
            SELECT Approval_Status__c, Approval_Note__c, Decided_On__c, Decided_By__c
            FROM Decision__c WHERE Id = :d.Id
        ];
        System.assertEquals('Approved', saved.Approval_Status__c);
        System.assertEquals('Checked with grid desk', saved.Approval_Note__c);
        System.assertNotEquals(null, saved.Decided_On__c);
        System.assertEquals(UserInfo.getUserId(), saved.Decided_By__c);

        for (Action__c a : [SELECT Status__c FROM Action__c WHERE Decision__c = :d.Id]) {
            System.assertEquals('Planned', a.Status__c);
        }
    }

    @IsTest
    static void rejectMovesActionsToRejected() {
        Decision__c d = pendingDecision();
        RenewAIApprovalService.permissionOverride = true;

        RenewAIDTO.ApprovalResponse out = RenewAIApprovalService.decide(
            req(d.Id, 'Rejected', 'Confidence too low'), 'TEST-2');

        System.assertEquals('Rejected', out.approvalStatus);
        for (Action__c a : [SELECT Status__c FROM Action__c WHERE Decision__c = :d.Id]) {
            System.assertEquals('Rejected', a.Status__c);
        }
    }

    @IsTest
    static void userWithoutPermissionIsRefused() {
        Decision__c d = pendingDecision();
        RenewAIApprovalService.permissionOverride = false;

        try {
            RenewAIApprovalService.decide(req(d.Id, 'Approved', null), 'TEST-3');
            System.assert(false, 'Expected RenewAIAccessException');
        } catch (RenewAIAccessException e) {
            System.assert(e.getMessage().contains('cannot approve'));
        }

        System.assertEquals('Pending', [
            SELECT Approval_Status__c FROM Decision__c WHERE Id = :d.Id
        ].Approval_Status__c);
    }

    @IsTest
    static void rejectNeedsANote() {
        assertValidation(
            req(pendingDecision().Id, 'Rejected', ''), 'NOTE_REQUIRED');
    }

    @IsTest
    static void badOutcomeIsRefused() {
        assertValidation(
            req(pendingDecision().Id, 'Maybe', 'x'), 'INVALID_OUTCOME');
    }

    @IsTest
    static void alreadyDecidedIsRefused() {
        Decision__c d = pendingDecision();
        RenewAIApprovalService.permissionOverride = true;
        RenewAIApprovalService.decide(req(d.Id, 'Approved', null), 'TEST-4');
        assertValidation(req(d.Id, 'Approved', null), 'NOT_PENDING');
    }

    @IsTest
    static void unknownAndMalformedIdsAreRefused() {
        assertValidation(req('abc', 'Approved', null), 'INVALID_ID');
        // A valid-looking Id that does not exist
        assertValidation(
            req(Decision__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA',
                'Approved', null),
            'NOT_FOUND');
    }

    @IsTest
    static void auditListsNewestFirstWithCountsAndFilter() {
        Decision__c d = pendingDecision();
        RenewAIApprovalService.permissionOverride = true;

        RenewAIDTO.AuditResponse everything = RenewAIAuditService.recent(null, null, 'TEST-5');
        System.assertEquals(true, everything.canApprove);
        System.assertEquals(1, everything.rows.size());
        System.assertEquals(d.Id, everything.rows[0].decisionId);
        System.assertEquals(2, everything.rows[0].actionCount);

        System.assertEquals(
            1, RenewAIAuditService.recent(10, 'Pending', 'TEST-6').rows.size());
        System.assertEquals(
            0, RenewAIAuditService.recent(10, 'Approved', 'TEST-7').rows.size());

        try {
            RenewAIAuditService.recent(10, 'Bogus', 'TEST-8');
            System.assert(false, 'Expected a validation error');
        } catch (RenewAIValidationException e) {
            System.assertEquals('INVALID_STATUS', e.validationErrors[0].code);
        }
    }
}
