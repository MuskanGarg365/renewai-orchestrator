/**
 * Read-only audit trail: the most recent decisions with their approval
 * status, who decided, the correlation id and the number of actions.
 */
public with sharing class RenewAIAuditService {

    public static final Integer DEFAULT_LIMIT = 20;
    public static final Integer MAX_LIMIT = 50;

    public static RenewAIDTO.AuditResponse recent(
        Integer requestedLimit,
        String statusFilter,
        String correlationId
    ) {
        Integer maxRows = requestedLimit == null
            ? DEFAULT_LIMIT
            : Math.min(Math.max(requestedLimit, 1), MAX_LIMIT);

        if (String.isNotBlank(statusFilter)
            && !new Set<String>{
                'Not Required', 'Pending', 'Approved', 'Rejected'
            }.contains(statusFilter)) {
            throw new RenewAIValidationException(
                new List<RenewAIDTO.ErrorDetail>{
                    new RenewAIDTO.ErrorDetail(
                        'status', 'INVALID_STATUS',
                        'status must be Not Required, Pending, Approved or Rejected.')
                });
        }

        List<Decision__c> rows = String.isBlank(statusFilter)
            ? [
                SELECT Id, Name, Decision_Type__c, Objective_Mode__c,
                    Approval_Status__c, Approval_Note__c, Confidence__c,
                    Score__c, Snapshot_Time__c, Correlation_Id__c,
                    Decided_On__c, Decided_By__r.Name, CreatedDate
                FROM Decision__c
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT :maxRows
            ]
            : [
                SELECT Id, Name, Decision_Type__c, Objective_Mode__c,
                    Approval_Status__c, Approval_Note__c, Confidence__c,
                    Score__c, Snapshot_Time__c, Correlation_Id__c,
                    Decided_On__c, Decided_By__r.Name, CreatedDate
                FROM Decision__c
                WHERE Approval_Status__c = :statusFilter
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT :maxRows
            ];

        RenewAIDTO.AuditResponse response = new RenewAIDTO.AuditResponse();
        response.correlationId = correlationId;
        response.canApprove = RenewAIApprovalService.canApprove();

        Map<Id, Integer> actionCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Decision__c did, COUNT(Id) n
            FROM Action__c
            WHERE Decision__c IN :rows
            WITH USER_MODE
            GROUP BY Decision__c
        ]) {
            actionCounts.put((Id) ar.get('did'), (Integer) ar.get('n'));
        }

        for (Decision__c d : rows) {
            RenewAIDTO.AuditRow row = new RenewAIDTO.AuditRow();
            row.decisionId = d.Id;
            row.name = d.Name;
            row.decisionType = d.Decision_Type__c;
            row.objectiveMode = d.Objective_Mode__c;
            row.approvalStatus = d.Approval_Status__c;
            row.approvalNote = d.Approval_Note__c;
            row.confidence = d.Confidence__c;
            row.score = d.Score__c;
            row.snapshotTime = d.Snapshot_Time__c;
            row.correlationId = d.Correlation_Id__c;
            row.decidedOn = d.Decided_On__c;
            row.decidedBy = d.Decided_By__r == null ? null : d.Decided_By__r.Name;
            row.createdDate = d.CreatedDate;
            row.actionCount = actionCounts.containsKey(d.Id)
                ? actionCounts.get(d.Id)
                : 0;
            response.rows.add(row);
        }
        return response;
    }
}
