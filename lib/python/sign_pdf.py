#!/usr/bin/env python3
# #547 (Hans, 2026-06-08): PAdES-Signatur (AES) auf ein PDF anwenden.
# Aufruf: python sign_pdf.py <key.pem> <cert.pem> <in.pdf> <out.pdf> <reason>
# Selbst-verwaltetes Zertifikat => fortgeschrittene elektronische Signatur:
# eindeutig dem Unterzeichner zugeordnet + manipulationssicher.
import sys
from pyhanko.sign import signers
from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter

key, cert, inp, outp, reason = sys.argv[1:6]
signer = signers.SimpleSigner.load(key, cert)
with open(inp, "rb") as f:
    w = IncrementalPdfFileWriter(f)
    meta = signers.PdfSignatureMetadata(field_name="Signature1", reason=reason, location="miolimOS")
    out = signers.sign_pdf(w, meta, signer=signer)
with open(outp, "wb") as f:
    f.write(out.getbuffer())
