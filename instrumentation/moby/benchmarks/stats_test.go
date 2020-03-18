package test

import (
	"encoding/csv"
	"encoding/json"
	"strconv"
	"strings"
	"testing"
	"time"
)

// Used to test marshalling speed of CSV/JSON
// End result: CSV is around 2.5x faster than JSON
//   However, this excludes including Pre-CPU stats, since CSV
//  i s designed for a long-table format, and duplicating row data
//   is unnecessary

type ThrottlingData struct {
	// Number of periods with throttling active
	Periods uint64 `json:"periods"`
	// Number of periods when the container hits its throttling limit.
	ThrottledPeriods uint64 `json:"throttled_periods"`
	// Aggregate time the container was throttled for in nanoseconds.
	ThrottledTime uint64 `json:"throttled_time"`
}

// CPUUsage stores All CPU stats aggregated since container inception.
type CPUUsage struct {
	// Total CPU time consumed.
	// Units: nanoseconds (Linux)
	// Units: 100's of nanoseconds (Windows)
	TotalUsage uint64 `json:"total_usage"`

	// Total CPU time consumed per core (Linux). Not used on Windows.
	// Units: nanoseconds.
	PercpuUsage []uint64 `json:"percpu_usage,omitempty"`

	// Time spent by tasks of the cgroup in kernel mode (Linux).
	// Time spent by all container processes in kernel mode (Windows).
	// Units: nanoseconds (Linux).
	// Units: 100's of nanoseconds (Windows). Not populated for Hyper-V Containers.
	UsageInKernelmode uint64 `json:"usage_in_kernelmode"`

	// Time spent by tasks of the cgroup in user mode (Linux).
	// Time spent by all container processes in user mode (Windows).
	// Units: nanoseconds (Linux).
	// Units: 100's of nanoseconds (Windows). Not populated for Hyper-V Containers
	UsageInUsermode uint64 `json:"usage_in_usermode"`
}

// CPUStats aggregates and wraps all CPU related info of container
type CPUStats struct {
	// CPU Usage. Linux and Windows.
	CPUUsage CPUUsage `json:"cpu_usage"`

	// System Usage. Linux only.
	SystemUsage uint64 `json:"system_cpu_usage,omitempty"`

	// Online CPUs. Linux only.
	OnlineCPUs uint32 `json:"online_cpus,omitempty"`

	// Throttling Data. Linux only.
	ThrottlingData ThrottlingData `json:"throttling_data,omitempty"`
}

// MemoryStats aggregates all memory stats since container inception on Linux.
// Windows returns stats for commit and private working set only.
type MemoryStats struct {
	// Linux Memory Stats

	// current res_counter usage for memory
	Usage uint64 `json:"usage,omitempty"`
	// maximum usage ever recorded.
	MaxUsage uint64 `json:"max_usage,omitempty"`
	// TODO(vishh): Export these as stronger types.
	// all the stats exported via memory.stat.
	Stats map[string]uint64 `json:"stats,omitempty"`
	// number of times memory usage hits limits.
	Failcnt uint64 `json:"failcnt,omitempty"`
	Limit   uint64 `json:"limit,omitempty"`

	// Windows Memory Stats
	// See https://technet.microsoft.com/en-us/magazine/ff382715.aspx

	// committed bytes
	Commit uint64 `json:"commitbytes,omitempty"`
	// peak committed bytes
	CommitPeak uint64 `json:"commitpeakbytes,omitempty"`
	// private working set
	PrivateWorkingSet uint64 `json:"privateworkingset,omitempty"`
}

// BlkioStatEntry is one small entity to store a piece of Blkio stats
// Not used on Windows.
type BlkioStatEntry struct {
	Major uint64 `json:"major"`
	Minor uint64 `json:"minor"`
	Op    string `json:"op"`
	Value uint64 `json:"value"`
}

// BlkioStats stores All IO service stats for data read and write.
// This is a Linux specific structure as the differences between expressing
// block I/O on Windows and Linux are sufficiently significant to make
// little sense attempting to morph into a combined structure.
type BlkioStats struct {
	// number of bytes transferred to and from the block device
	IoServiceBytesRecursive []BlkioStatEntry `json:"io_service_bytes_recursive"`
	IoServicedRecursive     []BlkioStatEntry `json:"io_serviced_recursive"`
	IoQueuedRecursive       []BlkioStatEntry `json:"io_queue_recursive"`
	IoServiceTimeRecursive  []BlkioStatEntry `json:"io_service_time_recursive"`
	IoWaitTimeRecursive     []BlkioStatEntry `json:"io_wait_time_recursive"`
	IoMergedRecursive       []BlkioStatEntry `json:"io_merged_recursive"`
	IoTimeRecursive         []BlkioStatEntry `json:"io_time_recursive"`
	SectorsRecursive        []BlkioStatEntry `json:"sectors_recursive"`
}

// StorageStats is the disk I/O stats for read/write on Windows.
type StorageStats struct {
	ReadCountNormalized  uint64 `json:"read_count_normalized,omitempty"`
	ReadSizeBytes        uint64 `json:"read_size_bytes,omitempty"`
	WriteCountNormalized uint64 `json:"write_count_normalized,omitempty"`
	WriteSizeBytes       uint64 `json:"write_size_bytes,omitempty"`
}

// NetworkStats aggregates the network stats of one container
type NetworkStats struct {
	// Bytes received. Windows and Linux.
	RxBytes uint64 `json:"rx_bytes"`
	// Packets received. Windows and Linux.
	RxPackets uint64 `json:"rx_packets"`
	// Received errors. Not used on Windows. Note that we don't `omitempty` this
	// field as it is expected in the >=v1.21 API stats structure.
	RxErrors uint64 `json:"rx_errors"`
	// Incoming packets dropped. Windows and Linux.
	RxDropped uint64 `json:"rx_dropped"`
	// Bytes sent. Windows and Linux.
	TxBytes uint64 `json:"tx_bytes"`
	// Packets sent. Windows and Linux.
	TxPackets uint64 `json:"tx_packets"`
	// Sent errors. Not used on Windows. Note that we don't `omitempty` this
	// field as it is expected in the >=v1.21 API stats structure.
	TxErrors uint64 `json:"tx_errors"`
	// Outgoing packets dropped. Windows and Linux.
	TxDropped uint64 `json:"tx_dropped"`
	// Endpoint ID. Not used on Linux.
	EndpointID string `json:"endpoint_id,omitempty"`
	// Instance ID. Not used on Linux.
	InstanceID string `json:"instance_id,omitempty"`
}

// PidsStats contains the stats of a container's pids
type PidsStats struct {
	// Current is the number of pids in the cgroup
	Current uint64 `json:"current,omitempty"`
	// Limit is the hard limit on the number of pids in the cgroup.
	// A "Limit" of 0 means that there is no limit.
	Limit uint64 `json:"limit,omitempty"`
}

// Stats is Ultimate struct aggregating all types of stats of one container
type Stats struct {
	// Common stats
	Read    time.Time `json:"read"`
	PreRead time.Time `json:"preread"`

	// Linux specific stats, not populated on Windows.
	PidsStats  PidsStats  `json:"pids_stats,omitempty"`
	BlkioStats BlkioStats `json:"blkio_stats,omitempty"`

	// Windows specific stats, not populated on Linux.
	NumProcs     uint32       `json:"num_procs"`
	StorageStats StorageStats `json:"storage_stats,omitempty"`

	// Shared stats
	CPUStats    CPUStats    `json:"cpu_stats,omitempty"`
	PreCPUStats CPUStats    `json:"precpu_stats,omitempty"` // "Pre"="Previous"
	MemoryStats MemoryStats `json:"memory_stats,omitempty"`
}

// StatsJSON is newly used Networks
type StatsJSON struct {
	Stats

	Name string `json:"name,omitempty"`
	ID   string `json:"id,omitempty"`

	// Networks request version >=1.21
	Networks map[string]NetworkStats `json:"networks,omitempty"`
}

var Result string

func BenchmarkJson(b *testing.B) {
	var res string
	var stats StatsJSON
	jsonStr := `{"read":"2020-03-16T07:50:25.077520621Z","preread":"2020-03-16T07:50:25.021748136Z","pids_stats":{"current":1},"blkio_stats":{"io_service_bytes_recursive":[{"major":8,"minor":0,"op":"Read","value":3833856},{"major":8,"minor":0,"op":"Write","value":0},{"major":8,"minor":0,"op":"Sync","value":3833856},{"major":8,"minor":0,"op":"Async","value":0},{"major":8,"minor":0,"op":"Total","value":3833856}],"io_serviced_recursive":[{"major":8,"minor":0,"op":"Read","value":82},{"major":8,"minor":0,"op":"Write","value":0},{"major":8,"minor":0,"op":"Sync","value":82},{"major":8,"minor":0,"op":"Async","value":0},{"major":8,"minor":0,"op":"Total","value":82}],"io_queue_recursive":[{"major":8,"minor":0,"op":"Read","value":0},{"major":8,"minor":0,"op":"Write","value":0},{"major":8,"minor":0,"op":"Sync","value":0},{"major":8,"minor":0,"op":"Async","value":0},{"major":8,"minor":0,"op":"Total","value":0}],"io_service_time_recursive":[{"major":8,"minor":0,"op":"Read","value":43507650},{"major":8,"minor":0,"op":"Write","value":0},{"major":8,"minor":0,"op":"Sync","value":43507650},{"major":8,"minor":0,"op":"Async","value":0},{"major":8,"minor":0,"op":"Total","value":43507650}],"io_wait_time_recursive":[{"major":8,"minor":0,"op":"Read","value":40718900},{"major":8,"minor":0,"op":"Write","value":0},{"major":8,"minor":0,"op":"Sync","value":40718900},{"major":8,"minor":0,"op":"Async","value":0},{"major":8,"minor":0,"op":"Total","value":40718900}],"io_merged_recursive":[{"major":8,"minor":0,"op":"Read","value":0},{"major":8,"minor":0,"op":"Write","value":0},{"major":8,"minor":0,"op":"Sync","value":0},{"major":8,"minor":0,"op":"Async","value":0},{"major":8,"minor":0,"op":"Total","value":0}],"io_time_recursive":[{"major":8,"minor":0,"op":"","value":81638984}],"sectors_recursive":[{"major":8,"minor":0,"op":"","value":7488}]},"num_procs":0,"storage_stats":{},"cpu_stats":{"cpu_usage":{"total_usage":39231615,"percpu_usage":[39231615],"usage_in_kernelmode":0,"usage_in_usermode":0},"system_cpu_usage":12161520000000,"online_cpus":1,"throttling_data":{"periods":0,"throttled_periods":0,"throttled_time":0}},"precpu_stats":{"cpu_usage":{"total_usage":39231615,"percpu_usage":[39231615],"usage_in_kernelmode":0,"usage_in_usermode":0},"system_cpu_usage":12161470000000,"online_cpus":1,"throttling_data":{"periods":0,"throttled_periods":0,"throttled_time":0}},"memory_stats":{"usage":4902912,"max_usage":5386240,"stats":{"active_anon":413696,"active_file":2797568,"cache":3833856,"dirty":0,"hierarchical_memory_limit":9223372036854771712,"hierarchical_memsw_limit":0,"inactive_anon":0,"inactive_file":1036288,"mapped_file":3010560,"pgfault":1411,"pgmajfault":33,"pgpgin":1728,"pgpgout":691,"rss":413696,"rss_huge":0,"total_active_anon":413696,"total_active_file":2797568,"total_cache":3833856,"total_dirty":0,"total_inactive_anon":0,"total_inactive_file":1036288,"total_mapped_file":3010560,"total_pgfault":1411,"total_pgmajfault":33,"total_pgpgin":1728,"total_pgpgout":691,"total_rss":413696,"total_rss_huge":0,"total_unevictable":0,"total_writeback":0,"unevictable":0,"writeback":0},"limit":1033015296},"network":{"rx_bytes":0,"rx_packets":0,"rx_errors":0,"rx_dropped":0,"tx_bytes":0,"tx_packets":0,"tx_errors":0,"tx_dropped":0}}`
	json.Unmarshal([]byte(jsonStr), &stats)
	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		res = TJson(b, &stats)
	}
	Result = res
}

func BenchmarkCsv(b *testing.B) {
	var res string
	var stats StatsJSON
	jsonStr := `{"read":"2020-03-16T07:50:25.077520621Z","preread":"2020-03-16T07:50:25.021748136Z","pids_stats":{"current":1},"blkio_stats":{"io_service_bytes_recursive":[{"major":8,"minor":0,"op":"Read","value":3833856},{"major":8,"minor":0,"op":"Write","value":0},{"major":8,"minor":0,"op":"Sync","value":3833856},{"major":8,"minor":0,"op":"Async","value":0},{"major":8,"minor":0,"op":"Total","value":3833856}],"io_serviced_recursive":[{"major":8,"minor":0,"op":"Read","value":82},{"major":8,"minor":0,"op":"Write","value":0},{"major":8,"minor":0,"op":"Sync","value":82},{"major":8,"minor":0,"op":"Async","value":0},{"major":8,"minor":0,"op":"Total","value":82}],"io_queue_recursive":[{"major":8,"minor":0,"op":"Read","value":0},{"major":8,"minor":0,"op":"Write","value":0},{"major":8,"minor":0,"op":"Sync","value":0},{"major":8,"minor":0,"op":"Async","value":0},{"major":8,"minor":0,"op":"Total","value":0}],"io_service_time_recursive":[{"major":8,"minor":0,"op":"Read","value":43507650},{"major":8,"minor":0,"op":"Write","value":0},{"major":8,"minor":0,"op":"Sync","value":43507650},{"major":8,"minor":0,"op":"Async","value":0},{"major":8,"minor":0,"op":"Total","value":43507650}],"io_wait_time_recursive":[{"major":8,"minor":0,"op":"Read","value":40718900},{"major":8,"minor":0,"op":"Write","value":0},{"major":8,"minor":0,"op":"Sync","value":40718900},{"major":8,"minor":0,"op":"Async","value":0},{"major":8,"minor":0,"op":"Total","value":40718900}],"io_merged_recursive":[{"major":8,"minor":0,"op":"Read","value":0},{"major":8,"minor":0,"op":"Write","value":0},{"major":8,"minor":0,"op":"Sync","value":0},{"major":8,"minor":0,"op":"Async","value":0},{"major":8,"minor":0,"op":"Total","value":0}],"io_time_recursive":[{"major":8,"minor":0,"op":"","value":81638984}],"sectors_recursive":[{"major":8,"minor":0,"op":"","value":7488}]},"num_procs":0,"storage_stats":{},"cpu_stats":{"cpu_usage":{"total_usage":39231615,"percpu_usage":[39231615],"usage_in_kernelmode":0,"usage_in_usermode":0},"system_cpu_usage":12161520000000,"online_cpus":1,"throttling_data":{"periods":0,"throttled_periods":0,"throttled_time":0}},"precpu_stats":{"cpu_usage":{"total_usage":39231615,"percpu_usage":[39231615],"usage_in_kernelmode":0,"usage_in_usermode":0},"system_cpu_usage":12161470000000,"online_cpus":1,"throttling_data":{"periods":0,"throttled_periods":0,"throttled_time":0}},"memory_stats":{"usage":4902912,"max_usage":5386240,"stats":{"active_anon":413696,"active_file":2797568,"cache":3833856,"dirty":0,"hierarchical_memory_limit":9223372036854771712,"hierarchical_memsw_limit":0,"inactive_anon":0,"inactive_file":1036288,"mapped_file":3010560,"pgfault":1411,"pgmajfault":33,"pgpgin":1728,"pgpgout":691,"rss":413696,"rss_huge":0,"total_active_anon":413696,"total_active_file":2797568,"total_cache":3833856,"total_dirty":0,"total_inactive_anon":0,"total_inactive_file":1036288,"total_mapped_file":3010560,"total_pgfault":1411,"total_pgmajfault":33,"total_pgpgin":1728,"total_pgpgout":691,"total_rss":413696,"total_rss_huge":0,"total_unevictable":0,"total_writeback":0,"unevictable":0,"writeback":0},"limit":1033015296},"network":{"rx_bytes":0,"rx_packets":0,"rx_errors":0,"rx_dropped":0,"tx_bytes":0,"tx_packets":0,"tx_errors":0,"tx_dropped":0}}`
	json.Unmarshal([]byte(jsonStr), &stats)
	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		res = TCsv(b, &stats)
	}
	Result = res
}

func TJson(b *testing.B, stats *StatsJSON) string {
	b.StopTimer()
	var strWriter strings.Builder
	jsonEncoder := json.NewEncoder(&strWriter)
	encode := func(stats interface{}) error {
		return jsonEncoder.Encode(stats)
	}
	b.StartTimer()

	encode(stats)

	b.StopTimer()
	return strWriter.String()
}

func TCsv(b *testing.B, stats *StatsJSON) string {
	b.StopTimer()
	var strWriter strings.Builder
	csvEncoder := csv.NewWriter(&strWriter)

	encode := func(s interface{}) error {
		stats := *(s.(*StatsJSON))
		record := [...]string{
			Int64(stats.Read.UnixNano()),
			Int64(stats.PreRead.UnixNano()),
			stats.Name,
			stats.ID,
			Uint64(stats.CPUStats.CPUUsage.TotalUsage),
			Uint64Array(stats.CPUStats.CPUUsage.PercpuUsage),
			Uint64(stats.CPUStats.CPUUsage.UsageInKernelmode),
			Uint64(stats.CPUStats.CPUUsage.UsageInUsermode),
			Uint64(stats.CPUStats.SystemUsage),
			Uint32(stats.CPUStats.OnlineCPUs),
			Uint64(stats.CPUStats.ThrottlingData.Periods),
			Uint64(stats.CPUStats.ThrottlingData.ThrottledPeriods),
			Uint64(stats.CPUStats.ThrottlingData.ThrottledTime),
			Uint64(stats.MemoryStats.Usage),
			Uint64(stats.MemoryStats.MaxUsage),
			MapStringUint64(&stats.MemoryStats.Stats),
			Uint64(stats.MemoryStats.Failcnt),
			Uint64(stats.MemoryStats.Limit),
			Uint64(stats.MemoryStats.Commit),
			Uint64(stats.MemoryStats.CommitPeak),
			Uint64(stats.MemoryStats.PrivateWorkingSet),
			Uint64(stats.PidsStats.Current),
			Uint64(stats.PidsStats.Limit),
			Uint32(stats.NumProcs),
			Uint64(stats.StorageStats.ReadCountNormalized),
			Uint64(stats.StorageStats.ReadSizeBytes),
			Uint64(stats.StorageStats.WriteCountNormalized),
			Uint64(stats.StorageStats.WriteSizeBytes),
			BlkioArray(&stats.BlkioStats.IoServiceBytesRecursive),
			BlkioArray(&stats.BlkioStats.IoServicedRecursive),
			BlkioArray(&stats.BlkioStats.IoQueuedRecursive),
			BlkioArray(&stats.BlkioStats.IoServiceTimeRecursive),
			BlkioArray(&stats.BlkioStats.IoWaitTimeRecursive),
			BlkioArray(&stats.BlkioStats.IoMergedRecursive),
			BlkioArray(&stats.BlkioStats.IoTimeRecursive),
			BlkioArray(&stats.BlkioStats.SectorsRecursive),
			MapStringNetworkStats(&stats.Networks),
		}

		return csvEncoder.Write(record[:])
	}
	b.StartTimer()

	encode(stats)
	csvEncoder.Flush()

	b.StopTimer()
	return strWriter.String()
}

func Uint64(u uint64) string {
	return strconv.FormatUint(u, 10)
}

func Int64(i int64) string {
	return strconv.FormatInt(i, 10)
}

func Uint32(u uint32) string {
	return Uint64(uint64(u))
}

func Uint64Array(a []uint64) string {
	if len(a) == 0 {
		return ""
	}

	var str strings.Builder
	last := len(a) - 1
	for i, v := range a {
		str.WriteString(strconv.FormatUint(v, 10))
		if i != last {
			str.WriteRune(',')
		}
	}
	return str.String()
}

func MapStringUint64(m *map[string]uint64) string {
	var str strings.Builder
	str.WriteRune('{')
	for key, element := range *m {
		str.WriteString(key)
		str.WriteRune(':')
		str.WriteString(strconv.FormatUint(element, 10))
		str.WriteRune(',')
	}
	str.WriteRune('}')
	return str.String()
}

func BlkioArray(a *[]BlkioStatEntry) string {
	if len(*a) == 0 {
		return ""
	}

	var str strings.Builder
	last := len(*a) - 1
	for i, v := range *a {
		str.WriteString(strconv.FormatUint(v.Major, 10))
		str.WriteRune(' ')
		str.WriteString(strconv.FormatUint(v.Minor, 10))
		str.WriteRune(' ')
		str.WriteString(strconv.FormatUint(v.Value, 10))
		str.WriteRune(' ')
		str.WriteString(v.Op)
		if i != last {
			str.WriteRune(',')
		}
	}
	return str.String()
}

func MapStringNetworkStats(n *map[string]NetworkStats) string {
	var str strings.Builder
	str.WriteRune('{')
	for key, element := range *n {
		str.WriteString(key)
		str.WriteString(":\"")
		WriteNetworkStats(&element, &str)
		str.WriteString("\",")
	}
	str.WriteRune('}')
	return str.String()
}

func WriteNetworkStats(n *NetworkStats, str *strings.Builder) {
	str.WriteString(strconv.FormatUint(n.RxBytes, 10))
	str.WriteRune(' ')
	str.WriteString(strconv.FormatUint(n.RxPackets, 10))
	str.WriteRune(' ')
	str.WriteString(strconv.FormatUint(n.RxErrors, 10))
	str.WriteRune(' ')
	str.WriteString(strconv.FormatUint(n.RxDropped, 10))
	str.WriteRune('|')
	str.WriteString(strconv.FormatUint(n.TxBytes, 10))
	str.WriteRune(' ')
	str.WriteString(strconv.FormatUint(n.TxPackets, 10))
	str.WriteRune(' ')
	str.WriteString(strconv.FormatUint(n.TxErrors, 10))
	str.WriteRune(' ')
	str.WriteString(strconv.FormatUint(n.TxDropped, 10))
}
