using System;
using Microsoft.VisualStudio.Settings;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Settings;

namespace GuitkxVsix
{
    // Persists the three GUITKX language-server options through a WritableSettingsStore under an
    // explicit named collection, instead of DialogPage's default reflection-derived registry path.
    //
    // This is deliberate, not incidental: GuitkxLanguageClient.ActivateAsync (a MEF component that
    // activates on file content-type) can fire before GuitkxPackage is sited -- packages load lazily
    // and VS does not coordinate that with MEF activation at all (there is no documented/supported
    // way to force package-before-client ordering). Reading options via
    // AsyncPackage.GetGlobalService/ServiceProvider.GlobalProvider through the package instance would
    // therefore silently serve hardcoded defaults on a fresh VS start whenever a .guitkx-associated
    // file is among the first things opened. A WritableSettingsStore read only needs
    // SVsSettingsManager, a core shell service VS itself proffers regardless of whether GuitkxPackage
    // has loaded -- so both GuitkxOptionsPage (writing) and GuitkxLanguageClient (reading) go through
    // this same collection directly, and the read path is correct by construction, not by luck.
    internal static class GuitkxSettings
    {
        private const string CollectionPath = "GUITKX\\Options";
        private const string KeyEnableEmbeddedAnalysis = "EnableEmbeddedAnalysis";
        private const string KeyUseGdformat = "UseGdformat";
        private const string KeyEnableGdscriptAnalysis = "EnableGdscriptAnalysis";
        private const string KeyFormatOnSave = "FormatOnSave";

        public struct Options
        {
            public bool EnableEmbeddedAnalysis;
            public bool UseGdformat;
            public bool EnableGdscriptAnalysis;
            public bool FormatOnSave;
        }

        public static readonly Options Defaults = new Options
        {
            EnableEmbeddedAnalysis = true,
            UseGdformat = true,
            EnableGdscriptAnalysis = true,
            // Matches VS Code's configurationDefaults (editor.formatOnSave: true for [guitkx]).
            FormatOnSave = true,
        };

        private static WritableSettingsStore GetStore(IServiceProvider serviceProvider)
        {
            var settingsManager = new ShellSettingsManager(serviceProvider);
            return settingsManager.GetWritableSettingsStore(SettingsScope.UserSettings);
        }

        public static Options Read(IServiceProvider serviceProvider)
        {
            var store = GetStore(serviceProvider);
            if (!store.CollectionExists(CollectionPath))
                return Defaults;

            return new Options
            {
                EnableEmbeddedAnalysis = store.GetBoolean(CollectionPath, KeyEnableEmbeddedAnalysis, Defaults.EnableEmbeddedAnalysis),
                UseGdformat = store.GetBoolean(CollectionPath, KeyUseGdformat, Defaults.UseGdformat),
                EnableGdscriptAnalysis = store.GetBoolean(CollectionPath, KeyEnableGdscriptAnalysis, Defaults.EnableGdscriptAnalysis),
                FormatOnSave = store.GetBoolean(CollectionPath, KeyFormatOnSave, Defaults.FormatOnSave),
            };
        }

        public static void Write(IServiceProvider serviceProvider, Options options)
        {
            var store = GetStore(serviceProvider);
            if (!store.CollectionExists(CollectionPath))
                store.CreateCollection(CollectionPath);

            store.SetBoolean(CollectionPath, KeyEnableEmbeddedAnalysis, options.EnableEmbeddedAnalysis);
            store.SetBoolean(CollectionPath, KeyUseGdformat, options.UseGdformat);
            store.SetBoolean(CollectionPath, KeyEnableGdscriptAnalysis, options.EnableGdscriptAnalysis);
            store.SetBoolean(CollectionPath, KeyFormatOnSave, options.FormatOnSave);
        }
    }
}
