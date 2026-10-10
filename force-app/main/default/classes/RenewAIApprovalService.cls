/**
 * Human-in-the-loop gate. A decision whose approval status is Pending
 * (low confidence or high reliability risk) can only move to Approved or
 * Rejected by a user holding the RenewAI_Approve_Decisions custom
 * permission. Its actions move with it: Awaiting Approval becomes Planned
 * (approved) or Rejected.
 */
public with sharing class RenewAIApprovalService {

    public static final String PERMISSION = 'RenewAI_Approve_Decisions';

    /** Tests set this to true or false to skip the real permission lookup. */
    @TestVisible
    private static Boolean permissionOverride;

    public static Boolean canApprove() {
        if (permissionOverride != null) {
            return permissionOverride;
        }
        return FeatureManagement.checkPermission(PERMISSION);
    }

    public static RenewAIDTO.ApprovalResponse decide(
        RenewAIDTO.ApprovalRequest request,
        String correlationId
    ) {
        List<RenewAIDTO.ErrorDetail> errors =
            new List<RenewAIDTO.ErrorDetail>();

        if (request == null) {
            errors.add(new RenewAIDTO.ErrorDetail(
                'request', 'REQUIRED', 'An approval request is required.'));
            throw new RenewAIValidationException(errors);
        }
        if (String.isBlank(request.decisionId)) {
            errors.add(new RenewAIDTO.ErrorDetail(
                'decisionId', 'REQUIRED', 'decisionId is required.'));
        }
        if (request.outcome != 'Approved' && request.outcome != 'Rejected') {
            errors.add(new RenewAIDTO.ErrorDetail(
                'outcome', 'INVALID_OUTCOME',
                'outcome must be Approved or Rejected.'));
        }
        if (request.outcome == 'Rejected' && String.isBlank(request.note)) {
            errors.add(new RenewAIDTO.ErrorDetail(
                'note', 'NOTE_REQUIRED',
                'A note is required when rejecting a decision.'));
        }
        if (request.note != null && request.note.length() > 255) {
            errors.add(new RenewAIDTO.ErrorDetail(
                'note', 'NOTE_TOO_LONG', 'The note is limited to 255 characters.'));
        }
        if (!errors.isEmpty()) {
            throw new RenewAIValidationException(errors);
        }

        // Permission is checked after validation so a bad request is a 400
        // for everyone, but never reveals decision data to a non-approver.
        if (!canApprove()) {
            throw new RenewAIAccessException(
                'The current user cannot approve or reject decisions.');
        }

        Id decisionId;
        try {
            decisionId = Id.valueOf(request.decisionId);
        } catch (Exception e) {
            throw new RenewAIValidationException(
                new List<RenewAIDTO.ErrorDetail>{
                    new RenewAIDTO.ErrorDetail(
                        'decisionId', 'INVALID_ID',
                        'decisionId is not a valid record Id.')
                });
        }

        List<Decision__c> found = [
            SELECT Id, Approval_Status__c
            FROM Decision__c
            WHERE Id = :decisionId
            WITH USER_MODE
            LIMIT 1
        ];
        if (found.isEmpty()) {
            throw new RenewAIValidationException(
                new List<RenewAIDTO.ErrorDetail>{
                    new RenewAIDTO.ErrorDetail(
                        'decisionId', 'NOT_FOUND', 'The decision was not found.')
                });
        }

        Decision__c decision = found[0];
        if (decision.Approval_Status__c != 'Pending') {
            throw new RenewAIValidationException(
                new List<RenewAIDTO.ErrorDetail>{
                    new RenewAIDTO.ErrorDetail(
                        'decisionId', 'NOT_PENDING',
                        'Only decisions that are Pending can be approved or rejected. Current status: '
                        + decision.Approval_Status__c)
                });
        }

        decision.Approval_Status__c = request.outcome;
        decision.Approval_Note__c = request.note;
        decision.Decided_On__c = Datetime.now();
        decision.Decided_By__c = UserInfo.getUserId();
        update as user decision;

        List<Action__c> actions = [
            SELECT Id, Status__c
            FROM Action__c
            WHERE Decision__c = :decisionId
            AND Status__c = 'Awaiting Approval'
            WITH USER_MODE
        ];
        for (Action__c a : actions) {
            a.Status__c = request.outcome == 'Approved' ? 'Planned' : 'Rejected';
        }
        if (!actions.isEmpty()) {
            update as user actions;
        }

        RenewAIDTO.ApprovalResponse response =
            new RenewAIDTO.ApprovalResponse();
        response.correlationId = correlationId;
        response.decisionId = decisionId;
        response.approvalStatus = request.outcome;
        response.actionsUpdated = actions.size();
        response.decidedBy = UserInfo.getName();
        response.decidedOn = decision.Decided_On__c;
        return response;
    }
}
