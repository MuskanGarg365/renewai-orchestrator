/**
 * Shared helpers for the Agentforce actions: correlation IDs, a fixed demo
 * clock, number formatting and one place that turns any exception into a
 * structured error the agent can read (instead of an unhandled flow fault).
 */
public with sharing class RenewAIAgentSupport {

    // The seeded data is synthetic and covers 2026-10-09 UTC. The agent uses
    // this snapshot when the user does not name a time, so it never has to
    // ask for a timestamp. 06:30Z is 12:00 IST.
    public static final String DEFAULT_AS_OF = '2026-10-09T06:30:00Z';

    public class Failure {
        public String errorCode;
        public String message;
    }

    public static String newCorrelationId() {
        String source = String.valueOf(Crypto.getRandomLong()) +
            Datetime.now().getTime();
        return 'RENEWAI-' + EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(source))
        ).substring(0, 12).toUpperCase();
    }

    // Accepts 2026-10-09T06:30:00Z or 2026-10-09 06:30:00; blank = demo clock.
    public static Datetime parseAsOf(String value) {
        String text = String.isBlank(value) ? DEFAULT_AS_OF : value.trim();
        try {
            String normalized = text.replace('T', ' ').replace('Z', '');
            Integer dot = normalized.indexOf('.');
            if (dot > -1) {
                normalized = normalized.substring(0, dot);
            }
            return Datetime.valueOfGmt(normalized);
        } catch (Exception exceptionRecord) {
            throw new RenewAIValidationException(
                new List<RenewAIDTO.ErrorDetail>{
                    new RenewAIDTO.ErrorDetail(
                        'asOf',
                        'INVALID_DATETIME',
                        'Use UTC format YYYY-MM-DDTHH:mm:ssZ.'
                    )
                }
            );
        }
    }

    public static Failure toFailure(
        Exception exceptionRecord,
        String correlationId
    ) {
        Failure failure = new Failure();

        if (exceptionRecord instanceof RenewAIValidationException) {
            RenewAIValidationException v =
                (RenewAIValidationException) exceptionRecord;
            RenewAIDTO.ErrorDetail first = v.validationErrors.isEmpty()
                ? null
                : v.validationErrors[0];
            failure.errorCode = first == null ? 'VALIDATION_ERROR' : first.code;
            failure.message = first == null
                ? 'The request failed validation.'
                : first.message;
        } else if (exceptionRecord instanceof QueryException) {
            failure.errorCode = 'ACCESS_DENIED';
            failure.message =
                'The agent user cannot read the RenewAI data. Assign the RenewAI permission sets.';
        } else if (exceptionRecord instanceof DmlException) {
            failure.errorCode = 'SAVE_FAILED';
            failure.message = 'RenewAI could not save the result.';
        } else {
            failure.errorCode = 'INTERNAL_ERROR';
            failure.message = 'RenewAI could not process the request.';
        }

        System.debug(
            LoggingLevel.ERROR,
            'RenewAI agent action correlationId=' + correlationId +
            ', exceptionType=' + exceptionRecord.getTypeName() +
            ', message=' + exceptionRecord.getMessage()
        );
        return failure;
    }

    public static String num(Decimal value) {
        return value == null
            ? ''
            : value.setScale(2, System.RoundingMode.HALF_UP).toPlainString();
    }

    public static String describeActions(List<RenewAIDTO.ActionLine> actions) {
        if (actions == null || actions.isEmpty()) {
            return 'No action required';
        }
        List<String> parts = new List<String>();
        for (RenewAIDTO.ActionLine line : actions) {
            parts.add(
                line.actionType + ' ' + num(line.quantityMW) +
                ' MW (' + line.assetCode + ')'
            );
        }
        return String.join(parts, '; ');
    }

    public static String describeRejected(
        List<RenewAIDTO.CandidateResult> rejected
    ) {
        if (rejected == null || rejected.isEmpty()) {
            return 'None';
        }
        List<String> parts = new List<String>();
        for (RenewAIDTO.CandidateResult r : rejected) {
            parts.add(r.label + ' (' + String.join(r.rejectionReasons, ', ') + ')');
        }
        return String.join(parts, '; ');
    }

    public static String describeScore(
        List<RenewAIDTO.TermScore> breakdown
    ) {
        if (breakdown == null || breakdown.isEmpty()) {
            return '';
        }
        List<String> parts = new List<String>();
        for (RenewAIDTO.TermScore t : breakdown) {
            parts.add(t.term + ' ' + num(t.contribution));
        }
        return String.join(parts, ', ');
    }
}
