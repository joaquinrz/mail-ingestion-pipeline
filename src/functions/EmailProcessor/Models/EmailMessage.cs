namespace EmailProcessor.Models;

/// <summary>
/// Represents an email message received from the Service Bus queue.
/// </summary>
public sealed record EmailMessage
{
    /// <summary>
    /// Gets the email subject line.
    /// </summary>
    public string? Subject { get; init; }

    /// <summary>
    /// Gets the sender email address.
    /// </summary>
    public string? From { get; init; }

    /// <summary>
    /// Gets the date and time the email was received.
    /// </summary>
    public string? ReceivedDateTime { get; init; }

    /// <summary>
    /// Gets a preview of the email body content.
    /// </summary>
    public string? BodyPreview { get; init; }
}
