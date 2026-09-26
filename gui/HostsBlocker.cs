using System.Diagnostics;
using System.Text;

namespace gui
{
    internal static class HostsBlocker
    {
        internal const string BeginMarker = "# BEGIN NewOutlookAdBlocker-2026";
        internal const string EndMarker = "# END NewOutlookAdBlocker-2026";

        // Accepted only for cleanup/migration from experimental builds.
        private const string AlternateBeginMarker = "# BEGIN NewOutlookPatcher-NOAB";
        private const string AlternateEndMarker = "# END NewOutlookPatcher-NOAB";

        internal static readonly string[] Domains =
        {
            "msft-ssp.adnxs.com",
            "msft-ssp-fra1.adnxs.com",
            "eb2.3lift.com",
            "b1t-dubdc2.outbrain.com",
        };

        internal static string HostsPath =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "drivers", "etc", "hosts");

        private static string BackupDirectory =>
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "NewOutlookPatcher-NOAB"
            );

        internal static bool IsInstalled()
        {
            try
            {
                string text = ReadHostsText(out _);
                string managed = GetManagedBlock(text, BeginMarker, EndMarker);
                if (string.IsNullOrEmpty(managed))
                    return false;

                foreach (string domain in Domains)
                {
                    if (!managed.Contains($"0.0.0.0 {domain}", StringComparison.OrdinalIgnoreCase))
                        return false;
                }

                return true;
            }
            catch
            {
                return false;
            }
        }

        internal static void Apply(bool enabled)
        {
            string hostsPath = HostsPath;
            if (!File.Exists(hostsPath))
                throw new FileNotFoundException("The Windows hosts file was not found.", hostsPath);

            byte[] originalBytes = File.ReadAllBytes(hostsPath);
            string originalText = DecodeHosts(originalBytes, out Encoding encoding, out bool emitPreamble);

            string newline = originalText.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
            string updated = RemoveManagedBlock(originalText, BeginMarker, EndMarker);
            updated = RemoveManagedBlock(updated, AlternateBeginMarker, AlternateEndMarker);

            if (enabled)
            {
                updated = updated.TrimEnd('\r', '\n');
                if (updated.Length > 0)
                    updated += newline + newline;

                updated += BeginMarker + newline;
                foreach (string domain in Domains)
                    updated += $"0.0.0.0 {domain}{newline}";
                updated += EndMarker + newline;
            }
            else
            {
                // Do not restore an old whole-file backup and do not normalize
                // unrelated content. Removing our marker block is the only edit.
            }

            if (!string.Equals(originalText, updated, StringComparison.Ordinal))
            {
                BackupBeforeChange(hostsPath);
                WriteHostsText(hostsPath, updated, encoding, emitPreamble);
            }

            bool actual = IsInstalled();
            if (actual != enabled)
            {
                throw new IOException(
                    enabled
                        ? "The NOAB hosts block could not be verified after installation."
                        : "The NOAB hosts block could not be verified as removed."
                );
            }

            FlushDns();
        }

        private static string GetManagedBlock(string text, string beginMarker, string endMarker)
        {
            int begin = text.IndexOf(beginMarker, StringComparison.Ordinal);
            if (begin < 0)
                return "";

            int end = text.IndexOf(endMarker, begin + beginMarker.Length, StringComparison.Ordinal);
            if (end < 0)
                return "";

            end += endMarker.Length;
            return text.Substring(begin, end - begin);
        }

        private static string RemoveManagedBlock(string text, string beginMarker, string endMarker)
        {
            while (true)
            {
                int begin = text.IndexOf(beginMarker, StringComparison.Ordinal);
                if (begin < 0)
                    return text;

                int end = text.IndexOf(endMarker, begin + beginMarker.Length, StringComparison.Ordinal);
                if (end < 0)
                {
                    // Malformed marker: do not truncate unrelated hosts content.
                    return text;
                }

                end += endMarker.Length;

                // Consume the line ending after the managed block when present.
                if (end < text.Length && text[end] == '\r')
                    end++;
                if (end < text.Length && text[end] == '\n')
                    end++;

                text = text.Remove(begin, end - begin);
            }
        }

        private static string ReadHostsText(out Encoding encoding)
        {
            byte[] bytes = File.ReadAllBytes(HostsPath);
            string text = DecodeHosts(bytes, out encoding, out _);
            return text;
        }

        private static string DecodeHosts(byte[] bytes, out Encoding encoding, out bool emitPreamble)
        {
            emitPreamble = false;
            int offset = 0;

            if (bytes.Length >= 3 &&
                bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
            {
                encoding = new UTF8Encoding(true);
                emitPreamble = true;
                offset = 3;
            }
            else if (bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
            {
                encoding = Encoding.Unicode;
                emitPreamble = true;
                offset = 2;
            }
            else if (bytes.Length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF)
            {
                encoding = Encoding.BigEndianUnicode;
                emitPreamble = true;
                offset = 2;
            }
            else
            {
                try
                {
                    var strictUtf8 = new UTF8Encoding(false, true);
                    _ = strictUtf8.GetString(bytes);
                    encoding = new UTF8Encoding(false);
                }
                catch (DecoderFallbackException)
                {
                    // Latin-1 provides a byte-preserving fallback for legacy comments.
                    encoding = Encoding.Latin1;
                }
            }

            return encoding.GetString(bytes, offset, bytes.Length - offset);
        }

        private static void WriteHostsText(string path, string text, Encoding encoding, bool emitPreamble)
        {
            byte[] content = encoding.GetBytes(text);
            byte[] preamble = emitPreamble ? encoding.GetPreamble() : Array.Empty<byte>();

            using FileStream stream = new FileStream(
                path,
                FileMode.Create,
                FileAccess.Write,
                FileShare.Read
            );

            if (preamble.Length > 0)
                stream.Write(preamble, 0, preamble.Length);

            stream.Write(content, 0, content.Length);
            stream.Flush(true);
        }

        private static void BackupBeforeChange(string hostsPath)
        {
            Directory.CreateDirectory(BackupDirectory);

            string originalBackup = Path.Combine(BackupDirectory, "hosts.original.bak");
            if (!File.Exists(originalBackup))
                File.Copy(hostsPath, originalBackup, false);

            string lastBackup = Path.Combine(BackupDirectory, "hosts.before-last-change.bak");
            File.Copy(hostsPath, lastBackup, true);
        }

        private static void FlushDns()
        {
            string ipconfig = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                "ipconfig.exe"
            );

            var psi = new ProcessStartInfo
            {
                FileName = ipconfig,
                Arguments = "/flushdns",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };

            using Process? process = Process.Start(psi);
            if (process == null)
                return;

            process.WaitForExit(10000);
        }
    }
}
