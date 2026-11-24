using System.Windows;

namespace DataCenterLauncher;

public partial class RepairDialog : Window
{
    public bool ClearShaderCache => ChkClearCache.IsChecked == true;
    public bool ResetConfigs => ChkResetConfig.IsChecked == true;
    public bool DeleteSaves => ChkDeleteSaves.IsChecked == true;

    public RepairDialog()
    {
        InitializeComponent();
    }

    private void CancelBtn_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    private void ConfirmBtn_Click(object sender, RoutedEventArgs e)
    {
        if (DeleteSaves)
        {
            var confirm = MessageBox.Show(
                "Bist du sicher, dass du ALLE lokalen Spielstände löschen möchtest?\n\n" +
                "Klicke auf [NEIN], um deine Spielstände sicher zu behalten und trotzdem zu reparieren.",
                "Spielstände wirklich löschen?",
                MessageBoxButton.YesNoCancel,
                MessageBoxImage.Warning);

            if (confirm == MessageBoxResult.Cancel) return;
            if (confirm == MessageBoxResult.No) ChkDeleteSaves.IsChecked = false;
        }

        DialogResult = true;
        Close();
    }
}
