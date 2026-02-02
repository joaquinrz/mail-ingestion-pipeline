using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using EmailProcessor.Models;

namespace EmailProcessor.Functions;

/// <summary>
/// Processes email messages from Service Bus queue.
/// </summary>
public sealed class EmailProcessorFunction(ILogger<EmailProcessorFunction> logger)
{
    /// <summary>
    /// Processes incoming email messages from the Service Bus queue.
    /// </summary>
    /// <param name="message">The Service Bus message containing email data.</param>
    /// <param name="messageActions">Actions for completing or dead-lettering the message.</param>
    /// <param name="cancellationToken">Cancellation token for the operation.</param>
    [Function(nameof(ProcessEmailMessage))]
    public async Task ProcessEmailMessage(
        [ServiceBusTrigger("email-messages", Connection = "ServiceBusConnection")]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        logger.LogInformation("Processing message ID: {MessageId}", message.MessageId);

        try
        {
            var emailData = JsonSerializer.Deserialize<EmailMessage>(message.Body);

            if (emailData is null)
            {
                logger.LogWarning("Failed to deserialize message {MessageId}", message.MessageId);
                await messageActions.DeadLetterMessageAsync(
                    message,
                    deadLetterReason: "InvalidFormat",
                    deadLetterErrorDescription: "Message body could not be deserialized",
                    cancellationToken: cancellationToken);
                return;
            }

            logger.LogInformation("Email received:");
            logger.LogInformation("  Subject: {Subject}", emailData.Subject);
            logger.LogInformation("  From: {From}", emailData.From);
            logger.LogInformation("  Received: {ReceivedDateTime}", emailData.ReceivedDateTime);

            var previewLength = Math.Min(100, emailData.BodyPreview?.Length ?? 0);
            if (previewLength > 0)
            {
                logger.LogInformation("  Preview: {Preview}...", emailData.BodyPreview![..previewLength]);
            }

            await messageActions.CompleteMessageAsync(message, cancellationToken);
            logger.LogInformation("Successfully processed message ID: {MessageId}", message.MessageId);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error processing message {MessageId}", message.MessageId);
            throw;
        }
    }
}
