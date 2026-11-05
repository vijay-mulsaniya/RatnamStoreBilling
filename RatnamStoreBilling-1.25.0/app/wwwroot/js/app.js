window.accountingApp = {
    print: function () {
        window.print();
    },

    /** A large file (a backup) sent as a stream: no base64 copy. */
    downloadStream: async function (fileName, streamRef, mimeType) {
        const buffer = await streamRef.arrayBuffer();
        window.accountingApp.saveBlob(new Blob([buffer], { type: mimeType }), fileName);
    },

    downloadBytes: function (fileName, base64, mimeType) {
        const binary = atob(base64);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

        window.accountingApp.saveBlob(new Blob([bytes], { type: mimeType }), fileName);
    },

    /**
     * Opens a PDF in a new tab. If the browser blocks the tab, the file is downloaded instead (returns false).
     */
    openPdf: function (fileName, base64) {
        const binary = atob(base64);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

        const blob = new Blob([bytes], { type: 'application/pdf' });
        const url = URL.createObjectURL(blob);
        const tab = window.open(url, '_blank');

        if (!tab) {
            URL.revokeObjectURL(url);
            window.accountingApp.saveBlob(blob, fileName);
            return false;
        }

        // Keep the address alive long enough for the tab to load it
        setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
        return true;
    },

    downloadText: function (fileName, text, mimeType) {
        window.accountingApp.saveBlob(
            new Blob([text], { type: mimeType || 'text/plain;charset=utf-8;' }), fileName);
    },

    /**
     * Prints one element (the counter receipt) by copying it into a hidden frame with the receipt
     * style sheet, so nothing else of the page is printed and no paper is wasted.
     * pageCss sets the paper, e.g. "@page { margin: 0; }".
     */
    printElement: function (elementId, pageCss, copies) {
        const source = document.getElementById(elementId);
        if (!source) return;

        // Copies (1 to 5) go in ONE print job, each on its own page (a thermal printer cuts between them)
        const count = Math.min(Math.max(parseInt(copies || 1, 10) || 1, 1), 5);
        let body = '';
        for (let i = 0; i < count; i++) {
            body += (i > 0 ? '<div style="break-before:page;page-break-before:always"></div>' : '') + source.outerHTML;
        }

        const frame = document.createElement('iframe');
        frame.setAttribute('aria-hidden', 'true');
        frame.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0;';
        document.body.appendChild(frame);

        const cssUrl = new URL('css/receipt.css', document.baseURI).href;
        const doc = frame.contentWindow.document;
        doc.open();
        doc.write('<!doctype html><html><head><meta charset="utf-8"><title>Receipt</title>' +
            '<link rel="stylesheet" href="' + cssUrl + '">' +
            '<style>' + (pageCss || '') + '</style></head>' +
            '<body class="receipt-print">' + body + '</body></html>');
        doc.close();

        let done = false;
        const go = function () {
            if (done) return;
            done = true;
            frame.contentWindow.focus();
            frame.contentWindow.print();
            setTimeout(function () { frame.remove(); }, 2000);
        };

        // Print when the style sheet is in (or after 1.5 seconds at the latest)
        const link = doc.querySelector('link');
        if (link) {
            link.onload = go;
            link.onerror = go;
        }
        setTimeout(go, 1500);
    },

    /**
     * Billing screen keys (Store mode). Works wherever the focus is, so a cashier who touched a tile
     * can still scan the next barcode without clicking the scan box first.
     *  - F2 / F8 / F9 go to .NET (OnHotKey) from anywhere on the page.
     *  - A barcode scanner types fast and ends with Enter. When the focus is NOT in a text box, those
     *    keys are collected here and sent to .NET (OnScan). A person typing slowly is not taken as a scan.
     */
    storeKeys: {
        _handler: null,
        start: function (dotnetRef) {
            window.accountingApp.storeKeys.stop();
            let buffer = '';
            let last = 0;

            const handler = function (e) {
                if (e.key === 'F2' || e.key === 'F8' || e.key === 'F9') {
                    e.preventDefault();
                    dotnetRef.invokeMethodAsync('OnHotKey', e.key);
                    return;
                }

                const t = e.target;
                const inBox = t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);
                if (inBox || e.ctrlKey || e.altKey || e.metaKey) { buffer = ''; return; }

                const now = Date.now();
                if (now - last > 80) buffer = '';      // a pause: start again (scanners send keys within a few ms)
                last = now;

                if (e.key === 'Enter') {
                    if (buffer.length >= 3) {
                        e.preventDefault();
                        dotnetRef.invokeMethodAsync('OnScan', buffer);
                    }
                    buffer = '';
                } else if (e.key.length === 1) {
                    buffer += e.key;
                }
            };

            document.addEventListener('keydown', handler, true);
            window.accountingApp.storeKeys._handler = handler;
        },
        stop: function () {
            const h = window.accountingApp.storeKeys._handler;
            if (h) document.removeEventListener('keydown', h, true);
            window.accountingApp.storeKeys._handler = null;
        }
    },

    saveBlob: function (blob, fileName) {
        const url = URL.createObjectURL(blob);

        const link = document.createElement('a');
        link.href = url;
        link.download = fileName;
        document.body.appendChild(link);
        link.click();

        document.body.removeChild(link);
        URL.revokeObjectURL(url);
    },

    // Copies text (the licence request). The clipboard API needs https or localhost; else the old way.
    copyText: async function (text) {
        try {
            if (navigator.clipboard && window.isSecureContext) { await navigator.clipboard.writeText(text); return true; }
        } catch (e) { /* the old way below */ }
        const box = document.createElement('textarea');
        box.value = text;
        box.style.position = 'fixed';
        box.style.opacity = '0';
        document.body.appendChild(box);
        box.select();
        let done = false;
        try { done = document.execCommand('copy'); } catch (e) { done = false; }
        document.body.removeChild(box);
        return done;
    }
};
