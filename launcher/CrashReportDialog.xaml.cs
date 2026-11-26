using System.Windows;
using System.Windows.Input;

namespace DataCenterLauncher;

/// <summary>Fragt nach einem Absturz, ob ein Absturzbericht (GitHub-Issue) vorbereitet werden soll.</summary>
public partial class CrashReportDialog : Window
{
    public CrashReportDialog(CrashAnalysis analysis)
    {
        InitializeComponent();
        ReasonText.Text = $"Grund: {analysis.Reason}";
        ErrorText.Text = analysis.ErrorLine;
        ErrorText.Visibility = string.IsNullOrWhiteSpace(analysis.ErrorLine) || analysis.Reason.Contains(analysis.ErrorLine)
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private void NotNowBtn_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
    }

    private void SendBtn_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = true;
    }

    private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left && e.ButtonState == MouseButtonState.Pressed)
        {
            try { DragMove(); } catch { }
        }
    }
}
