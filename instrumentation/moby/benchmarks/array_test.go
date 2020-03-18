package test

import (
	"encoding/json"
	"strconv"
	"strings"
	"testing"
)

// Used to test various methods of converting an integer array to string
// Winner: using strings.Builder from Go 1.10

var Result string

func BenchmarkIntToString2(b *testing.B) {
	var res string
	for i := 0; i < b.N; i++ {
		res = IntToString2()
	}
	Result = res
}

func BenchmarkIntToString3(b *testing.B) {
	var res string
	for i := 0; i < b.N; i++ {
		res = IntToString3()
	}
	Result = res
}

func BenchmarkJsonMarshall(b *testing.B) {
	var res string
	for i := 0; i < b.N; i++ {
		res = JsonMarshall()
	}
	Result = res
}

func IntToString2() string {
	a := []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13}
	b := make([]string, len(a))
	for i, v := range a {
		b[i] = strconv.Itoa(v)
	}

	return strings.Join(b, ",")
}

func IntToString3() string {
	a := []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13}

	var str strings.Builder
	last := len(a) - 1
	sep := ","
	for i, v := range a {
		str.WriteString(strconv.Itoa(v))
		str.WriteRune(' ')
		if i != last {
			str.WriteString(sep)
		}
	}
	return str.String()
}

func JsonMarshall() string {
	a := []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13}
	s, _ := json.Marshal(a)
	return string(s)
}
