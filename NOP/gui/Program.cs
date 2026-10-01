using Microsoft.Win32;

namespace gui
{
    internal static class Program
    {
        private const string IfeoPath =
            "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options\\olk.exe";

        private static string WorkerPath =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                         "NewOutlookPatcher.dll");

        [STAThread]
        static void Main(string[] args)
        {
            if (args.Length > 0)
            {
                Environment.Exit(RunElevatedCommand(args));
                return;
            }

            ApplicationConfiguration.Initialize();
            Application.Run(new Form1());
        }

        private static int RunElevatedCommand(string[] args)
        {
            try
            {
                if (!args[0].Equals("--apply", StringComparison.OrdinalIgnoreCase) ||
                    args.Length < 3)
                    throw new ArgumentException("Invalid command line.");

                string tempFolder = args[1];

                bool patcherOn = args.Any(x =>
                    x.Equals("--patcher-on", StringComparison.OrdinalIgnoreCase));
                bool patcherOff = args.Any(x =>
                    x.Equals("--patcher-off", StringComparison.OrdinalIgnoreCase));

                if (patcherOn == patcherOff)
                    throw new ArgumentException("Specify exactly one patcher state.");

                if (patcherOn)
                    InstallPatcher(tempFolder);
                else
                    UninstallPatcher();

                if (Form1.IsPatcherInstalled() != patcherOn)
                    throw new InvalidOperationException("Patcher state could not be verified.");

                return 0;
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "NewOutlookPatcher NOAB could not apply the Outlook UI patch.\r\n\r\n" +
                    ex.Message,
                    "NewOutlookPatcher NOAB",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 10;
            }
        }

        private static void InstallPatcher(string tempFolder)
        {
            string sourceWorker = Path.Combine(tempFolder, "NewOutlookPatcher.dll");
            if (!File.Exists(sourceWorker))
                throw new FileNotFoundException("The extracted worker DLL was not found.", sourceWorker);

            File.Copy(sourceWorker, WorkerPath, true);

            RegistryKey localMachine =
                RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);

            using RegistryKey reg = localMachine.CreateSubKey(IfeoPath, true)
                ?? throw new InvalidOperationException("Unable to create/open the olk.exe IFEO key.");

            int globalFlag = Convert.ToInt32(reg.GetValue("GlobalFlag") ?? 0);
            reg.SetValue("GlobalFlag", globalFlag | 0x100, RegistryValueKind.DWord);

            string verifierDlls = Convert.ToString(reg.GetValue("VerifierDlls")) ?? "";
            string[] existing = verifierDlls.Split(
                ' ',
                StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

            if (!existing.Any(x => x.Equals("NewOutlookPatcher.dll",
                                             StringComparison.OrdinalIgnoreCase)))
            {
                verifierDlls = string.IsNullOrWhiteSpace(verifierDlls)
                    ? "NewOutlookPatcher.dll"
                    : verifierDlls.Trim() + " NewOutlookPatcher.dll";

                reg.SetValue("VerifierDlls", verifierDlls, RegistryValueKind.String);
            }

            reg.Flush();
        }

        private static void UninstallPatcher()
        {
            RegistryKey localMachine =
                RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);

            using RegistryKey? reg = localMachine.OpenSubKey(IfeoPath, true);

            if (reg != null)
            {
                string verifierDlls = Convert.ToString(reg.GetValue("VerifierDlls")) ?? "";

                string[] remaining = verifierDlls.Split(
                    ' ',
                    StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                    .Where(x => !x.Equals("NewOutlookPatcher.dll",
                                          StringComparison.OrdinalIgnoreCase))
                    .ToArray();

                if (remaining.Length == 0)
                    reg.DeleteValue("VerifierDlls", false);
                else
                    reg.SetValue("VerifierDlls",
                                 string.Join(" ", remaining),
                                 RegistryValueKind.String);

                if (remaining.Length == 0)
                {
                    int globalFlag = Convert.ToInt32(reg.GetValue("GlobalFlag") ?? 0);
                    globalFlag &= ~0x100;

                    if (globalFlag == 0)
                        reg.DeleteValue("GlobalFlag", false);
                    else
                        reg.SetValue("GlobalFlag", globalFlag, RegistryValueKind.DWord);
                }

                reg.Flush();
            }

            if (File.Exists(WorkerPath))
                File.Delete(WorkerPath);

            using RegistryKey? verify = localMachine.OpenSubKey(IfeoPath, false);
            if (verify != null && verify.SubKeyCount == 0 && verify.ValueCount == 0)
            {
                verify.Close();
                localMachine.DeleteSubKeyTree(IfeoPath, false);
            }
        }
    }
}
