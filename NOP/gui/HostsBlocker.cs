namespace gui
{
    internal static class HostsBlocker
    {
        internal const string BeginMarker = "# BEGIN NewOutlookAdBlocker-2026";
        internal const string EndMarker = "# END NewOutlookAdBlocker-2026";

        internal static readonly string[] Domains =
        {
            "msft-ssp.adnxs.com",
            "msft-ssp-fra1.adnxs.com",
            "eb2.3lift.com",
            "b1t-dubdc2.outbrain.com",
        };

        internal static string HostsPath =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                         "drivers", "etc", "hosts");

        internal static bool IsInstalled()
        {
            try
            {
                if (!File.Exists(HostsPath)) return false;
                string text = File.ReadAllText(HostsPath);

                int begin = text.IndexOf(BeginMarker, StringComparison.Ordinal);
                if (begin < 0) return false;

                int end = text.IndexOf(EndMarker, begin + BeginMarker.Length, StringComparison.Ordinal);
                if (end < 0) return false;

                string block = text.Substring(begin, end + EndMarker.Length - begin);

                foreach (string domain in Domains)
                {
                    if (!block.Contains($"0.0.0.0 {domain}",
                                        StringComparison.OrdinalIgnoreCase))
                        return false;
                }

                return true;
            }
            catch
            {
                return false;
            }
        }
    }
}
