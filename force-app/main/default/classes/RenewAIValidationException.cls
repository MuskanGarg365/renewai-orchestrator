public class RenewAIValidationException extends Exception {

    public List<RenewAIDTO.ErrorDetail> validationErrors { get; set; }

    public RenewAIValidationException(List<RenewAIDTO.ErrorDetail> errors) {
        this.validationErrors = errors;
    }
}