@RestResource(urlMapping='/renewai/v1/*')
global with sharing class RenewAIRestResource {

    @HttpGet
    global static void doGet() {
        String correlationId = createCorrelationId();
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;

        response.addHeader('Content-Type', 'application/json');
        response.addHeader('X-Correlation-Id', correlationId);

        try {
            String resourcePath = getResourcePath(request.requestURI);

            if (resourcePath == 'portfolio') {
                handlePortfolio(request, response, correlationId);
            } else if (resourcePath == 'assets') {
                handleAssets(response, correlationId);
            } else {
                writeError(response, 404, correlationId, 'RESOURCE_NOT_FOUND',
                    'The requested RenewAI resource was not found.', new List<RenewAIDTO.ErrorDetail>());
            }
        } catch (RenewAIValidationException exceptionRecord) {
            writeError(response, 400, correlationId, 'VALIDATION_ERROR',
                'The request or portfolio data failed validation.', exceptionRecord.validationErrors);
        } catch (QueryException exceptionRecord) {
            writeError(response, 403, correlationId, 'ACCESS_DENIED',
                'The current user cannot access the requested data.', new List<RenewAIDTO.ErrorDetail>());
        } catch (Exception exceptionRecord) {
            System.debug(LoggingLevel.ERROR, 'RenewAI correlationId=' + correlationId +
                ', exceptionType=' + exceptionRecord.getTypeName() + ', message=' + exceptionRecord.getMessage());
            writeError(response, 500, correlationId, 'INTERNAL_ERROR',
                'RenewAI could not process the request.', new List<RenewAIDTO.ErrorDetail>());
        }
    }

    @HttpPost
    global static void doPost() {
        String correlationId = createCorrelationId();

        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;

        response.addHeader('Content-Type', 'application/json');
        response.addHeader('X-Correlation-Id', correlationId);

        try {
            String resourcePath = getResourcePath(request.requestURI);

            if (resourcePath == 'decision') {
                handleDecision(request, response, correlationId);
            } else {
                writeError(
                    response,
                    404,
                    correlationId,
                    'RESOURCE_NOT_FOUND',
                    'The requested RenewAI resource was not found.',
                    new List<RenewAIDTO.ErrorDetail>()
                );
            }
        } catch (RenewAIValidationException exceptionRecord) {
            writeError(
                response,
                400,
                correlationId,
                'VALIDATION_ERROR',
                'The request or portfolio data failed validation.',
                exceptionRecord.validationErrors
            );
        } catch (JSONException exceptionRecord) {
            writeError(
                response,
                400,
                correlationId,
                'INVALID_JSON',
                'The request body is not valid JSON.',
                new List<RenewAIDTO.ErrorDetail>()
            );
        } catch (QueryException exceptionRecord) {
            writeError(
                response,
                403,
                correlationId,
                'ACCESS_DENIED',
                'The current user cannot access the requested data.',
                new List<RenewAIDTO.ErrorDetail>()
            );
        } catch (DmlException exceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                'RenewAI correlationId=' + correlationId +
                ', dml=' + exceptionRecord.getMessage()
            );

            Boolean denied = exceptionRecord.getMessage()
                .contains('INSUFFICIENT_ACCESS');

            writeError(
                response,
                denied ? 403 : 500,
                correlationId,
                denied ? 'ACCESS_DENIED' : 'INTERNAL_ERROR',
                denied
                    ? 'The current user cannot save decisions.'
                    : 'RenewAI could not save the decision.',
                new List<RenewAIDTO.ErrorDetail>()
            );
        } catch (Exception exceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                'RenewAI correlationId=' + correlationId +
                ', exceptionType=' + exceptionRecord.getTypeName() +
                ', message=' + exceptionRecord.getMessage()
            );

            writeError(
                response,
                500,
                correlationId,
                'INTERNAL_ERROR',
                'RenewAI could not process the request.',
                new List<RenewAIDTO.ErrorDetail>()
            );
        }
    }

    private static void handleDecision(
        RestRequest request,
        RestResponse response,
        String correlationId
    ) {
        String body = request.requestBody == null
            ? ''
            : request.requestBody.toString();

        RenewAIDTO.DecisionRequest decisionRequest =
            String.isBlank(body)
                ? null
                : (RenewAIDTO.DecisionRequest) JSON.deserialize(
                    body,
                    RenewAIDTO.DecisionRequest.class
                );

        RenewAIDTO.DecisionResponse result =
            RenewAIDecisionService.run(decisionRequest, correlationId);

        response.statusCode = 200;
        response.responseBody = Blob.valueOf(JSON.serialize(result));
    }

    private static void handlePortfolio(RestRequest request, RestResponse response, String correlationId) {
        RenewAIDTO.PortfolioRequest portfolioRequest = new RenewAIDTO.PortfolioRequest();
        String asOfParameter = request.params.get('asOf');

        portfolioRequest.asOf = String.isBlank(asOfParameter) ? Datetime.now() : parseDatetime(asOfParameter);
        portfolioRequest.intervalMinutes = parseInteger(request.params.get('intervalMinutes'), 15);
        portfolioRequest.maximumAgeMinutes = parseInteger(request.params.get('maximumAgeMinutes'), 30);

        // Structured 400s for a bad asOf, interval or age.
        RenewAIInputValidator.validateRequest(portfolioRequest);

        RenewAIDTO.PortfolioResponse result = RenewAIPortfolioService.getPortfolio(portfolioRequest, correlationId);
        response.statusCode = 200;
        response.responseBody = Blob.valueOf(JSON.serialize(result));
    }

    private static void handleAssets(RestResponse response, String correlationId) {
        RenewAIDTO.AssetsResponse result = RenewAIPortfolioService.getAssets(correlationId);
        response.statusCode = 200;
        response.responseBody = Blob.valueOf(JSON.serialize(result));
    }

    private static String getResourcePath(String requestUri) {
        if (String.isBlank(requestUri)) return '';
        String normalized = requestUri.toLowerCase();
        if (normalized.endsWith('/portfolio')) return 'portfolio';
        if (normalized.endsWith('/assets')) return 'assets';
        if (normalized.endsWith('/decision')) return 'decision';
        return '';
    }

    private static Datetime parseDatetime(String inputValue) {
        if (String.isBlank(inputValue)) return null;

        try {
            String normalized = inputValue.replace('T', ' ').replace('Z', '');
            Integer decimalPosition = normalized.indexOf('.');
            if (decimalPosition > -1) {
                normalized = normalized.substring(0, decimalPosition);
            }
            return Datetime.valueOfGmt(normalized);
        } catch (Exception exceptionRecord) {
            throw new RenewAIValidationException(new List<RenewAIDTO.ErrorDetail>{
                new RenewAIDTO.ErrorDetail('asOf', 'INVALID_DATETIME', 'Use UTC format YYYY-MM-DDTHH:mm:ssZ.')
            });
        }
    }

    private static Integer parseInteger(String inputValue, Integer defaultValue) {
        if (String.isBlank(inputValue)) return defaultValue;

        try {
            return Integer.valueOf(inputValue);
        } catch (Exception exceptionRecord) {
            throw new RenewAIValidationException(new List<RenewAIDTO.ErrorDetail>{
                new RenewAIDTO.ErrorDetail('queryParameter', 'INVALID_INTEGER', 'The query parameter must be an integer.')
            });
        }
    }

    private static String createCorrelationId() {
        String uuidSource = String.valueOf(Crypto.getRandomLong()) + Datetime.now().getTime();
        return 'RENEWAI-' + EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(uuidSource))
        ).substring(0, 12).toUpperCase();
    }

    private static void writeError(RestResponse response, Integer statusCode, String correlationId,
        String errorCode, String message, List<RenewAIDTO.ErrorDetail> details) {
        RenewAIDTO.ErrorResponse errorResponse = new RenewAIDTO.ErrorResponse();
        errorResponse.correlationId = correlationId;
        errorResponse.errorCode = errorCode;
        errorResponse.message = message;
        errorResponse.errors = details == null ? new List<RenewAIDTO.ErrorDetail>() : details;
        response.statusCode = statusCode;
        response.responseBody = Blob.valueOf(JSON.serialize(errorResponse));
    }
}
