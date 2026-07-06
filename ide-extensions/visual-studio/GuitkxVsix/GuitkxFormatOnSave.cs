using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.ComponentModelHost;
using Microsoft.VisualStudio.Editor;
using Microsoft.VisualStudio.OLE.Interop;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.TextManager.Interop;
using Newtonsoft.Json.Linq;

namespace GuitkxVsix
{
    // Format-on-save for .guitkx (row 17 of the parity plan), matching VS Code's
    // configurationDefaults (editor.formatOnSave: true for [guitkx]). Advised against the Running
    // Document Table from GuitkxPackage.InitializeAsync; OnBeforeSave sends textDocument/formatting
    // to the shared server and applies the resulting edits to the buffer before the actual disk
    // write proceeds.
    //
    // This is the least-verified piece of the whole parity campaign: it depends on
    // ILanguageClientCustomMessage2 actually being invoked by VS's LSP client host (confirmed the
    // type exists in the referenced assembly; NOT confirmed live that AttachForCustomMessageAsync
    // fires or that Rpc.InvokeWithParameterObjectAsync round-trips correctly against this server),
    // and on IVsRunningDocTableEvents3.OnBeforeSave's synchronous-COM-to-async-JsonRpc bridging via
    // JoinableTaskFactory.Run behaving as expected under real save timing. Test this interactively
    // before anything else in Phase 3.
    internal sealed class GuitkxFormatOnSave : IVsRunningDocTableEvents3
    {
        private readonly IVsRunningDocumentTable _rdt;
        private readonly IComponentModel _componentModel;
        private readonly HashSet<uint> _formattingInProgress = new HashSet<uint>();

        private GuitkxFormatOnSave(IVsRunningDocumentTable rdt, IComponentModel componentModel)
        {
            _rdt = rdt;
            _componentModel = componentModel;
        }

        /// <summary>Advises the RDT and returns the cookie the caller must Unadvise on package dispose.</summary>
        public static uint Advise(IVsRunningDocumentTable rdt, IComponentModel componentModel)
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            var listener = new GuitkxFormatOnSave(rdt, componentModel);
            ErrorHandler.ThrowOnFailure(rdt.AdviseRunningDocTableEvents(listener, out var cookie));
            return cookie;
        }

        public int OnBeforeSave(uint docCookie)
        {
            ThreadHelper.ThrowIfNotOnUIThread();

            if (!GuitkxSettings.Read(ServiceProvider.GlobalProvider).FormatOnSave)
                return VSConstants.S_OK;
            if (GuitkxLanguageClient.Rpc == null)
                return VSConstants.S_OK; // server not attached yet -- never block the save on it
            if (!_formattingInProgress.Add(docCookie))
                return VSConstants.S_OK; // re-entrancy guard: our own edit must not re-trigger this

            try
            {
                _rdt.GetDocumentInfo(docCookie, out _, out _, out _, out var moniker, out _, out _, out var docData);
                if (moniker == null || !moniker.EndsWith(".guitkx", StringComparison.OrdinalIgnoreCase))
                    return VSConstants.S_OK;

                var buffer = GetTextBuffer(docData);
                if (buffer == null)
                    return VSConstants.S_OK;

                var uri = new Uri(moniker).AbsoluteUri;
                var requestParams = new
                {
                    textDocument = new { uri },
                    // guitkx's canonical formatting is spaces at width 2 (Unity-exact, since 0.7.0) --
                    // matches the formatter's own defaults regardless of what this says, but the LSP
                    // formatting request still requires an options object.
                    options = new { tabSize = 2, insertSpaces = true },
                };

                JToken result;
                try
                {
                    result = ThreadHelper.JoinableTaskFactory.Run(() =>
                        GuitkxLanguageClient.Rpc.InvokeWithParameterObjectAsync<JToken>("textDocument/formatting", requestParams));
                }
                catch (Exception)
                {
                    // Never block a save on a formatting failure (server down, request error, etc.).
                    return VSConstants.S_OK;
                }

                ApplyEdits(buffer, result);
            }
            finally
            {
                _formattingInProgress.Remove(docCookie);
            }

            return VSConstants.S_OK;
        }

        private static void ApplyEdits(ITextBuffer buffer, JToken editsToken)
        {
            if (editsToken == null || editsToken.Type != JTokenType.Array)
                return;

            var snapshot = buffer.CurrentSnapshot;
            using (var edit = buffer.CreateEdit())
            {
                foreach (var editToken in editsToken)
                {
                    var range = editToken["range"];
                    var newText = (string)editToken["newText"] ?? "";
                    var start = ToSnapshotPoint(snapshot, range["start"]);
                    var end = ToSnapshotPoint(snapshot, range["end"]);
                    if (start < 0 || end < 0 || end < start)
                        continue;
                    edit.Replace(Span.FromBounds(start, end), newText);
                }
                edit.Apply();
            }
        }

        // LSP positions are 0-based {line, character} (UTF-16 code units); ITextSnapshot lines and
        // Start+character composition match that directly for the plain-ASCII/BMP case this editor's
        // own content is expected to stay within.
        private static int ToSnapshotPoint(ITextSnapshot snapshot, JToken position)
        {
            var line = (int)position["line"];
            var character = (int)position["character"];
            if (line < 0 || line >= snapshot.LineCount)
                return -1;
            var snapshotLine = snapshot.GetLineFromLineNumber(line);
            var column = Math.Min(character, snapshotLine.Length);
            return snapshotLine.Start.Position + column;
        }

        private ITextBuffer GetTextBuffer(object docData)
        {
            if (docData is IVsTextBuffer vsTextBuffer)
            {
                var adapters = _componentModel.GetService<IVsEditorAdaptersFactoryService>();
                return adapters.GetDocumentBuffer(vsTextBuffer);
            }
            return null;
        }

        // -- IVsRunningDocTableEvents / 2 / 3: everything else is a no-op. --
        public int OnAfterFirstDocumentLock(uint docCookie, uint dwRDTLockType, uint dwReadLocksRemaining, uint dwEditLocksRemaining) => VSConstants.S_OK;
        public int OnBeforeLastDocumentUnlock(uint docCookie, uint dwRDTLockType, uint dwReadLocksRemaining, uint dwEditLocksRemaining) => VSConstants.S_OK;
        public int OnAfterSave(uint docCookie) => VSConstants.S_OK;
        public int OnAfterAttributeChange(uint docCookie, uint grfAttribs) => VSConstants.S_OK;
        public int OnBeforeDocumentWindowShow(uint docCookie, int fFirstShow, IVsWindowFrame pFrame) => VSConstants.S_OK;
        public int OnAfterDocumentWindowHide(uint docCookie, IVsWindowFrame pFrame) => VSConstants.S_OK;
        public int OnAfterAttributeChangeEx(uint docCookie, uint grfAttribs, IVsHierarchy pHierOld, uint itemidOld, string pszMkDocumentOld, IVsHierarchy pHierNew, uint itemidNew, string pszMkDocumentNew) => VSConstants.S_OK;
    }
}
