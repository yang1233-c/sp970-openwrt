// SPDX-License-Identifier: GPL-2.0-only
#include <glib.h>
#include <libqmi-glib.h>

static GMainLoop *loop;
static QmiDevice *device;
static QmiClient *client;
static guint8 slot = 1;
static gboolean activate = TRUE;
static GByteArray *aid;
static int exit_status = 1;

static void close_ready(QmiDevice *dev, GAsyncResult *res, gpointer unused)
{
    GError *error = NULL;
    (void)unused;
    if (!qmi_device_close_finish(dev, res, &error)) {
        g_printerr("close_error=%s\n", error->message);
        g_error_free(error);
    }
    g_main_loop_quit(loop);
}

static void close_device(void)
{
    qmi_device_close_async(device, 10, NULL,
                           (GAsyncReadyCallback)close_ready, NULL);
}

static void release_ready(QmiDevice *dev, GAsyncResult *res, gpointer unused)
{
    GError *error = NULL;
    (void)unused;
    if (!qmi_device_release_client_finish(dev, res, &error)) {
        g_printerr("release_error=%s\n", error->message);
        g_error_free(error);
    }
    g_clear_object(&client);
    close_device();
}

static void release_client(void)
{
    if (!client) {
        close_device();
        return;
    }
    qmi_device_release_client(device, client,
                              QMI_DEVICE_RELEASE_CLIENT_FLAGS_RELEASE_CID,
                              10, NULL,
                              (GAsyncReadyCallback)release_ready, NULL);
}

static void command_ready(QmiDevice *dev, GAsyncResult *res, gpointer unused)
{
    QmiMessage *response;
    GError *error = NULL;
    guint16 tlv_length = 0;
    guint16 result = 1;
    guint16 protocol_error = 0xffff;
    gsize tlv_offset;
    gsize value_offset = 0;
    (void)unused;

    response = qmi_device_command_full_finish(dev, res, &error);
    if (!response) {
        g_printerr("command_error=%s\n", error->message);
        g_error_free(error);
        release_client();
        return;
    }

    tlv_offset = qmi_message_tlv_read_init(response, 0x02, &tlv_length, &error);
    if (!tlv_offset || tlv_length != 4 ||
        !qmi_message_tlv_read_guint16(response, tlv_offset, &value_offset,
                                      QMI_ENDIAN_LITTLE, &result, &error) ||
        !qmi_message_tlv_read_guint16(response, tlv_offset, &value_offset,
                                      QMI_ENDIAN_LITTLE, &protocol_error, &error)) {
        g_printerr("response_parse_error=%s\n",
                   error ? error->message : "invalid result TLV");
        g_clear_error(&error);
    } else {
        g_print("operation=%s session=primary-gw slot=%u aid_length=%u result=%u protocol_error=%u\n",
                activate ? "activate" : "deactivate", slot, aid->len,
                result, protocol_error);
        if (result == 0 && protocol_error == 0)
            exit_status = 0;
    }

    qmi_message_unref(response);
    release_client();
}

static gboolean write_request(QmiMessage *message, GError **error)
{
    gsize tlv_offset;
    guint i;

    /* UIM 0x0038, TLV 0x01: primary-GW session (0), activate/deactivate. */
    tlv_offset = qmi_message_tlv_write_init(message, 0x01, error);
    if (!tlv_offset ||
        !qmi_message_tlv_write_guint8(message, 0, error) ||
        !qmi_message_tlv_write_guint8(message, activate ? 1 : 0, error) ||
        !qmi_message_tlv_write_complete(message, tlv_offset, error))
        return FALSE;

    /* TLV 0x10: slot, one-byte AID length, then AID bytes. */
    tlv_offset = qmi_message_tlv_write_init(message, 0x10, error);
    if (!tlv_offset ||
        !qmi_message_tlv_write_guint8(message, slot, error) ||
        !qmi_message_tlv_write_guint8(message, (guint8)aid->len, error))
        return FALSE;
    for (i = 0; i < aid->len; i++) {
        if (!qmi_message_tlv_write_guint8(message, aid->data[i], error))
            return FALSE;
    }
    return qmi_message_tlv_write_complete(message, tlv_offset, error);
}

static void allocate_ready(QmiDevice *dev, GAsyncResult *res, gpointer unused)
{
    QmiMessage *message;
    GError *error = NULL;
    (void)unused;

    client = qmi_device_allocate_client_finish(dev, res, &error);
    if (!client) {
        g_printerr("allocate_error=%s\n", error->message);
        g_error_free(error);
        close_device();
        return;
    }

    message = qmi_message_new(QMI_SERVICE_UIM,
                              qmi_client_get_cid(client),
                              1, 0x0038);
    if (!write_request(message, &error)) {
        g_printerr("request_build_error=%s\n", error ? error->message : "unknown");
        g_clear_error(&error);
        qmi_message_unref(message);
        release_client();
        return;
    }

    qmi_device_command_full(device, message, NULL, 15, NULL,
                            (GAsyncReadyCallback)command_ready, NULL);
    qmi_message_unref(message);
}

static void open_ready(QmiDevice *dev, GAsyncResult *res, gpointer unused)
{
    GError *error = NULL;
    (void)unused;
    if (!qmi_device_open_finish(dev, res, &error)) {
        g_printerr("open_error=%s\n", error->message);
        g_error_free(error);
        g_main_loop_quit(loop);
        return;
    }
    qmi_device_allocate_client(device, QMI_SERVICE_UIM, QMI_CID_NONE,
                               10, NULL,
                               (GAsyncReadyCallback)allocate_ready, NULL);
}

static void new_ready(GObject *unused, GAsyncResult *res, gpointer user_data)
{
    GError *error = NULL;
    (void)unused;
    (void)user_data;
    device = qmi_device_new_finish(res, &error);
    if (!device) {
        g_printerr("device_error=%s\n", error->message);
        g_error_free(error);
        g_main_loop_quit(loop);
        return;
    }
    qmi_device_open(device, QMI_DEVICE_OPEN_FLAGS_AUTO, 10, NULL,
                    (GAsyncReadyCallback)open_ready, NULL);
}

static gboolean parse_aid(const gchar *hex)
{
    const gchar *p;
    guint8 high = 0;
    gboolean have_high = FALSE;

    aid = g_byte_array_new();
    for (p = hex; *p; p++) {
        guint8 nibble;
        if (*p == ':' || *p == '-' || g_ascii_isspace(*p))
            continue;
        if (!g_ascii_isxdigit(*p))
            return FALSE;
        nibble = (guint8)g_ascii_xdigit_value(*p);
        if (!have_high) {
            high = nibble;
            have_high = TRUE;
        } else {
            guint8 byte = (guint8)((high << 4) | nibble);
            g_byte_array_append(aid, &byte, 1);
            have_high = FALSE;
        }
    }
    return !have_high && aid->len > 0 && aid->len <= 255;
}

int main(int argc, char **argv)
{
    GFile *file;
    guint64 parsed;

    if (argc != 5 ||
        (g_strcmp0(argv[2], "activate") != 0 &&
         g_strcmp0(argv[2], "deactivate") != 0)) {
        g_printerr("usage: %s DEVICE activate|deactivate SLOT AID_HEX\n", argv[0]);
        return 2;
    }
    activate = g_strcmp0(argv[2], "activate") == 0;
    parsed = g_ascii_strtoull(argv[3], NULL, 10);
    if (parsed < 1 || parsed > 5) {
        g_printerr("slot must be 1..5\n");
        return 2;
    }
    slot = (guint8)parsed;
    if (!parse_aid(argv[4])) {
        g_printerr("AID must contain 1..255 complete hex bytes\n");
        g_clear_pointer(&aid, g_byte_array_unref);
        return 2;
    }

    loop = g_main_loop_new(NULL, FALSE);
    file = g_file_new_for_path(argv[1]);
    qmi_device_new(file, NULL, (GAsyncReadyCallback)new_ready, NULL);
    g_object_unref(file);
    g_main_loop_run(loop);
    g_clear_object(&device);
    g_main_loop_unref(loop);
    g_clear_pointer(&aid, g_byte_array_unref);
    return exit_status;
}
