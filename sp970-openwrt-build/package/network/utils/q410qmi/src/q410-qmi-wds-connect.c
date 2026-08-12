// SPDX-License-Identifier: GPL-2.0-only
#include <arpa/inet.h>
#include <glib-unix.h>
#include <glib.h>
#include <glib/gstdio.h>
#include <libqmi-glib.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>

#define STATE_PATH "/tmp/q410-wds-ready.env"

static GMainLoop *loop;
static QmiDevice *device;
static QmiClientWds *wds;
static guint32 packet_handle;
static gboolean started;
static gboolean stopping;
static int exit_status = 1;
static gchar *apn;

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
    if (!device) {
        g_main_loop_quit(loop);
        return;
    }
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
    g_clear_object(&wds);
    close_device();
}

static void release_client(void)
{
    if (!wds) {
        close_device();
        return;
    }
    qmi_device_release_client(device, QMI_CLIENT(wds),
                              QMI_DEVICE_RELEASE_CLIENT_FLAGS_RELEASE_CID,
                              10, NULL,
                              (GAsyncReadyCallback)release_ready, NULL);
}

static void fail_and_release(const gchar *step, GError *error)
{
    g_printerr("state=failed step=%s error=%s\n", step,
               error ? error->message : "unknown");
    g_clear_error(&error);
    release_client();
}

static void stop_ready(QmiClientWds *client, GAsyncResult *res, gpointer unused)
{
    QmiMessageWdsStopNetworkOutput *output;
    GError *error = NULL;
    (void)unused;

    output = qmi_client_wds_stop_network_finish(client, res, &error);
    if (!output) {
        g_printerr("stop_error=%s\n", error->message);
        g_error_free(error);
    } else {
        if (!qmi_message_wds_stop_network_output_get_result(output, &error)) {
            g_printerr("stop_result_error=%s\n", error->message);
            g_error_free(error);
        } else {
            g_print("state=stopped handle=%u\n", packet_handle);
        }
        qmi_message_wds_stop_network_output_unref(output);
    }
    started = FALSE;
    release_client();
}

static gboolean stop_signal(gpointer unused)
{
    QmiMessageWdsStopNetworkInput *input;
    GError *error = NULL;
    (void)unused;

    if (stopping)
        return G_SOURCE_REMOVE;
    stopping = TRUE;
    g_unlink(STATE_PATH);
    if (!started) {
        release_client();
        return G_SOURCE_REMOVE;
    }

    input = qmi_message_wds_stop_network_input_new();
    if (!qmi_message_wds_stop_network_input_set_packet_data_handle(
            input, packet_handle, &error)) {
        qmi_message_wds_stop_network_input_unref(input);
        fail_and_release("build-stop", error);
        return G_SOURCE_REMOVE;
    }
    qmi_client_wds_stop_network(wds, input, 15, NULL,
                                (GAsyncReadyCallback)stop_ready, NULL);
    qmi_message_wds_stop_network_input_unref(input);
    return G_SOURCE_REMOVE;
}

static gchar *ipv4_string(guint32 value)
{
    struct in_addr addr;
    gchar buf[INET_ADDRSTRLEN];
    addr.s_addr = GUINT32_TO_BE(value);
    if (!inet_ntop(AF_INET, &addr, buf, sizeof(buf)))
        return g_strdup("");
    return g_strdup(buf);
}

static void current_settings_ready(QmiClientWds *client,
                                   GAsyncResult *res,
                                   gpointer unused)
{
    QmiMessageWdsGetCurrentSettingsOutput *output;
    GError *error = NULL;
    guint32 v4 = 0, gateway = 0, mask = 0, dns1 = 0, dns2 = 0, mtu = 0;
    gchar *v4s, *gws, *masks, *dns1s, *dns2s, *state;
    gsize state_len;
    (void)unused;

    output = qmi_client_wds_get_current_settings_finish(client, res, &error);
    if (!output) {
        fail_and_release("get-settings", error);
        return;
    }
    if (!qmi_message_wds_get_current_settings_output_get_result(output, &error)) {
        qmi_message_wds_get_current_settings_output_unref(output);
        fail_and_release("get-settings-result", error);
        return;
    }

    qmi_message_wds_get_current_settings_output_get_ipv4_address(output, &v4, NULL);
    qmi_message_wds_get_current_settings_output_get_ipv4_gateway_address(output, &gateway, NULL);
    qmi_message_wds_get_current_settings_output_get_ipv4_gateway_subnet_mask(output, &mask, NULL);
    qmi_message_wds_get_current_settings_output_get_primary_ipv4_dns_address(output, &dns1, NULL);
    qmi_message_wds_get_current_settings_output_get_secondary_ipv4_dns_address(output, &dns2, NULL);
    qmi_message_wds_get_current_settings_output_get_mtu(output, &mtu, NULL);
    qmi_message_wds_get_current_settings_output_unref(output);

    v4s = ipv4_string(v4);
    gws = ipv4_string(gateway);
    masks = ipv4_string(mask);
    dns1s = ipv4_string(dns1);
    dns2s = ipv4_string(dns2);
    state = g_strdup_printf(
        "STATE=connected\nCID=%u\nHANDLE=%u\nAPN=%s\nDATA_PORT=a2-mux-rmnet0\n"
        "IFACE=wwan0\nIPV4=%s\nGATEWAY=%s\nNETMASK=%s\nDNS1=%s\nDNS2=%s\nMTU=%u\n",
        qmi_client_get_cid(QMI_CLIENT(wds)), packet_handle, apn,
        v4s, gws, masks, dns1s, dns2s, mtu);
    state_len = strlen(state);
    if (!g_file_set_contents(STATE_PATH, state, state_len, &error)) {
        g_printerr("state_file_error=%s\n", error->message);
        g_error_free(error);
    }
    g_print("%s", state);
    fflush(stdout);
    g_free(state);
    g_free(dns2s);
    g_free(dns1s);
    g_free(masks);
    g_free(gws);
    g_free(v4s);

    exit_status = 0;
}

static void request_current_settings(void)
{
    QmiMessageWdsGetCurrentSettingsInput *input;
    QmiWdsRequestedSettings requested;
    GError *error = NULL;

    requested = QMI_WDS_REQUESTED_SETTINGS_DNS_ADDRESS |
                QMI_WDS_REQUESTED_SETTINGS_IP_ADDRESS |
                QMI_WDS_REQUESTED_SETTINGS_GATEWAY_INFO |
                QMI_WDS_REQUESTED_SETTINGS_MTU |
                QMI_WDS_REQUESTED_SETTINGS_IP_FAMILY;
    input = qmi_message_wds_get_current_settings_input_new();
    if (!qmi_message_wds_get_current_settings_input_set_requested_settings(
            input, requested, &error)) {
        qmi_message_wds_get_current_settings_input_unref(input);
        fail_and_release("build-get-settings", error);
        return;
    }
    qmi_client_wds_get_current_settings(wds, input, 15, NULL,
                                        (GAsyncReadyCallback)current_settings_ready,
                                        NULL);
    qmi_message_wds_get_current_settings_input_unref(input);
}

static void start_ready(QmiClientWds *client, GAsyncResult *res, gpointer unused)
{
    QmiMessageWdsStartNetworkOutput *output;
    GError *error = NULL;
    (void)unused;

    output = qmi_client_wds_start_network_finish(client, res, &error);
    if (!output) {
        fail_and_release("start-network", error);
        return;
    }
    if (!qmi_message_wds_start_network_output_get_result(output, &error)) {
        qmi_message_wds_start_network_output_unref(output);
        fail_and_release("start-network-result", error);
        return;
    }
    if (!qmi_message_wds_start_network_output_get_packet_data_handle(
            output, &packet_handle, &error)) {
        qmi_message_wds_start_network_output_unref(output);
        fail_and_release("start-network-handle", error);
        return;
    }
    qmi_message_wds_start_network_output_unref(output);
    started = TRUE;
    g_print("state=network-started cid=%u handle=%u\n",
            qmi_client_get_cid(QMI_CLIENT(wds)), packet_handle);
    request_current_settings();
}

static void start_network(void)
{
    QmiMessageWdsStartNetworkInput *input;
    GError *error = NULL;

    input = qmi_message_wds_start_network_input_new();
    if (!qmi_message_wds_start_network_input_set_apn(input, apn, &error) ||
        !qmi_message_wds_start_network_input_set_ip_family_preference(
            input, QMI_WDS_IP_FAMILY_IPV4, &error)) {
        qmi_message_wds_start_network_input_unref(input);
        fail_and_release("build-start-network", error);
        return;
    }
    qmi_client_wds_start_network(wds, input, 30, NULL,
                                 (GAsyncReadyCallback)start_ready, NULL);
    qmi_message_wds_start_network_input_unref(input);
}

static void set_family_ready(QmiClientWds *client,
                             GAsyncResult *res,
                             gpointer unused)
{
    QmiMessageWdsSetIpFamilyOutput *output;
    GError *error = NULL;
    (void)unused;

    output = qmi_client_wds_set_ip_family_finish(client, res, &error);
    if (!output) {
        fail_and_release("set-ip-family", error);
        return;
    }
    if (!qmi_message_wds_set_ip_family_output_get_result(output, &error)) {
        qmi_message_wds_set_ip_family_output_unref(output);
        fail_and_release("set-ip-family-result", error);
        return;
    }
    qmi_message_wds_set_ip_family_output_unref(output);
    g_print("state=ip-family-set family=4\n");
    start_network();
}

static void set_ip_family(void)
{
    QmiMessageWdsSetIpFamilyInput *input;
    GError *error = NULL;

    input = qmi_message_wds_set_ip_family_input_new();
    if (!qmi_message_wds_set_ip_family_input_set_preference(
            input, QMI_WDS_IP_FAMILY_IPV4, &error)) {
        qmi_message_wds_set_ip_family_input_unref(input);
        fail_and_release("build-set-ip-family", error);
        return;
    }
    qmi_client_wds_set_ip_family(wds, input, 15, NULL,
                                 (GAsyncReadyCallback)set_family_ready, NULL);
    qmi_message_wds_set_ip_family_input_unref(input);
}

static void bind_ready(QmiClientWds *client,
                       GAsyncResult *res,
                       gpointer unused)
{
    QmiMessageWdsBindDataPortOutput *output;
    GError *error = NULL;
    (void)unused;

    output = qmi_client_wds_bind_data_port_finish(client, res, &error);
    if (!output) {
        fail_and_release("bind-data-port", error);
        return;
    }
    if (!qmi_message_wds_bind_data_port_output_get_result(output, &error)) {
        qmi_message_wds_bind_data_port_output_unref(output);
        fail_and_release("bind-data-port-result", error);
        return;
    }
    qmi_message_wds_bind_data_port_output_unref(output);
    g_print("state=data-port-bound port=a2-mux-rmnet0\n");
    set_ip_family();
}

static void bind_data_port(void)
{
    QmiMessageWdsBindDataPortInput *input;
    GError *error = NULL;

    input = qmi_message_wds_bind_data_port_input_new();
    if (!qmi_message_wds_bind_data_port_input_set_data_port(
            input, QMI_SIO_PORT_A2_MUX_RMNET0, &error)) {
        qmi_message_wds_bind_data_port_input_unref(input);
        fail_and_release("build-bind-data-port", error);
        return;
    }
    qmi_client_wds_bind_data_port(wds, input, 15, NULL,
                                  (GAsyncReadyCallback)bind_ready, NULL);
    qmi_message_wds_bind_data_port_input_unref(input);
}

static void allocate_ready(QmiDevice *dev, GAsyncResult *res, gpointer unused)
{
    QmiClient *client;
    GError *error = NULL;
    (void)unused;

    client = qmi_device_allocate_client_finish(dev, res, &error);
    if (!client) {
        fail_and_release("allocate-wds", error);
        return;
    }
    wds = QMI_CLIENT_WDS(client);
    g_print("state=client-allocated cid=%u\n",
            qmi_client_get_cid(QMI_CLIENT(wds)));
    bind_data_port();
}

static void open_ready(QmiDevice *dev, GAsyncResult *res, gpointer unused)
{
    GError *error = NULL;
    (void)unused;
    if (!qmi_device_open_finish(dev, res, &error)) {
        g_printerr("state=failed step=open error=%s\n", error->message);
        g_error_free(error);
        g_main_loop_quit(loop);
        return;
    }
    qmi_device_allocate_client(device, QMI_SERVICE_WDS, QMI_CID_NONE,
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
        g_printerr("state=failed step=device-new error=%s\n", error->message);
        g_error_free(error);
        g_main_loop_quit(loop);
        return;
    }
    /* BAM-DMUX carries raw IPv4/IPv6 packets without an 802.3 or QoS header.
     * Negotiate that format through CTL before allocating the WDS client. */
    qmi_device_open(device,
                    QMI_DEVICE_OPEN_FLAGS_AUTO |
                    QMI_DEVICE_OPEN_FLAGS_NET_RAW_IP |
                    QMI_DEVICE_OPEN_FLAGS_NET_NO_QOS_HEADER,
                    10, NULL,
                    (GAsyncReadyCallback)open_ready, NULL);
}

int main(int argc, char **argv)
{
    GFile *file;

    if (argc != 3) {
        g_printerr("usage: %s DEVICE APN\n", argv[0]);
        return 2;
    }
    apn = g_strdup(argv[2]);
    g_unlink(STATE_PATH);
    loop = g_main_loop_new(NULL, FALSE);
    g_unix_signal_add(SIGINT, stop_signal, NULL);
    g_unix_signal_add(SIGTERM, stop_signal, NULL);
    file = g_file_new_for_path(argv[1]);
    qmi_device_new(file, NULL, (GAsyncReadyCallback)new_ready, NULL);
    g_object_unref(file);
    g_main_loop_run(loop);
    g_clear_object(&device);
    g_main_loop_unref(loop);
    g_free(apn);
    return exit_status;
}
